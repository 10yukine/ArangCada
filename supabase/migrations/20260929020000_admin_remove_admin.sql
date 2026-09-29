-- Offboarding administrators from the admin console.
--
-- Until now nothing could remove an admin: the console only managed invites,
-- and delete_account() refuses admin accounts. admin_remove_admin() lets an
-- LGU administrator turn another admin (LGU or TODA) back into an ordinary
-- account. It never removes the caller, so at least one LGU administrator
-- always remains. Their pending admin and driver invites are revoked (the
-- invite lookups already reject them once the inviter is no longer an admin).
-- The person can then delete their account themselves if they want to.
-- delete_account()'s refusal message now points at this instead of a
-- console feature that did not exist. Regression: 87_admin_remove_admin_test.sql.

-- A former admin's name stays on work they did as an admin. Those links go
-- NULL when they delete their account, like every other retained record.
alter table public.admin_invites
  alter column invited_by drop not null,
  drop constraint admin_invites_invited_by_fkey,
  add constraint admin_invites_invited_by_fkey foreign key (invited_by) references public.profiles (id) on delete set null;
alter table public.driver_invites
  alter column invited_by drop not null,
  drop constraint driver_invites_invited_by_fkey,
  add constraint driver_invites_invited_by_fkey foreign key (invited_by) references public.profiles (id) on delete set null;
alter table public.driver_profiles
  alter column promoted_by drop not null,
  drop constraint driver_profiles_promoted_by_fkey,
  add constraint driver_profiles_promoted_by_fkey foreign key (promoted_by) references public.profiles (id) on delete set null,
  drop constraint driver_profiles_reviewed_by_fkey,
  add constraint driver_profiles_reviewed_by_fkey foreign key (reviewed_by) references public.profiles (id) on delete set null;
alter table public.driver_documents
  drop constraint driver_documents_reviewed_by_fkey,
  add constraint driver_documents_reviewed_by_fkey foreign key (reviewed_by) references public.profiles (id) on delete set null;
alter table public.fare_class_claims
  drop constraint fare_class_claims_reviewed_by_fkey,
  add constraint fare_class_claims_reviewed_by_fkey foreign key (reviewed_by) references public.profiles (id) on delete set null;
alter table public.app_evaluation_settings
  drop constraint app_evaluation_settings_updated_by_fkey,
  add constraint app_evaluation_settings_updated_by_fkey foreign key (updated_by) references public.profiles (id) on delete set null;
alter table public.dispatch_settings
  drop constraint dispatch_settings_updated_by_fkey,
  add constraint dispatch_settings_updated_by_fkey foreign key (updated_by) references public.profiles (id) on delete set null;

create or replace function public.admin_remove_admin(p_admin_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can remove an administrator'
      using errcode = '42501';
  end if;
  if p_admin_id = auth.uid() then
    raise exception 'You cannot remove your own administrator access.'
      using errcode = '22023';
  end if;

  update public.profiles
     set role = 'commuter', updated_at = now()
   where id = p_admin_id and role = 'admin';
  if not found then
    raise exception 'This account is not an administrator.' using errcode = '22023';
  end if;

  delete from public.admin_scopes where admin_id = p_admin_id;
  update public.admin_invites set status = 'revoked'
   where invited_by = p_admin_id and status = 'pending';
  update public.driver_invites set status = 'revoked'
   where invited_by = p_admin_id and status = 'pending';

  insert into public.admin_audit_logs (actor_id, action, target_profile_id)
  values (auth.uid(), 'admin.removed', p_admin_id);
end;
$$;

revoke execute on function public.admin_remove_admin(uuid) from public, anon;
grant execute on function public.admin_remove_admin(uuid) to authenticated;

create or replace function public.delete_account(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_files   jsonb;
begin
  select * into v_profile from public.profiles where id = p_user_id for update;
  if not found then
    raise exception 'this account no longer exists' using errcode = 'P0002';
  end if;
  if v_profile.role = 'admin' then
    raise exception 'Administrator accounts cannot be deleted. Ask an LGU administrator to remove your admin access in the admin console, then delete your account.'
      using errcode = '55000';
  end if;
  if v_profile.email like '%@arangcada.demo' then
    raise exception 'Demo accounts cannot be deleted.' using errcode = '55000';
  end if;
  if exists (
    select 1 from public.trips
     where (rider_id = p_user_id or driver_id = p_user_id)
       and status in ('requested', 'searching_driver', 'driver_assigned', 'accepted',
                      'driver_en_route', 'arrived', 'in_progress', 'emergency_reported')
  ) then
    raise exception 'Finish or cancel your current ride before deleting your account.'
      using errcode = '55000';
  end if;

  -- Storage objects cannot be deleted from SQL; the caller removes these.
  v_files := jsonb_build_object(
    'profile-photos', coalesce(to_jsonb(array_remove(array[v_profile.avatar_path], null)), '[]'),
    'driver-documents', coalesce((select jsonb_agg(storage_path) from public.driver_documents
                                   where driver_id = p_user_id), '[]'),
    'discount-eligibility-ids', coalesce((select jsonb_agg(id_photo_path) from public.fare_class_claims
                                           where profile_id = p_user_id and id_photo_path is not null), '[]'),
    'trip-voice-notes', coalesce((select jsonb_agg(voice_path) from public.trip_messages
                                   where sender_id = p_user_id and voice_path is not null), '[]')
  );

  -- Kept records carry copies of the name; replace them before the link goes.
  update public.trips set rider_display_name = 'Deleted account' where rider_id = p_user_id;
  update public.trips set driver_display_name = 'Deleted account' where driver_id = p_user_id;
  update public.complaints set complainant_display_name = 'Deleted account' where complainant_id = p_user_id;
  update public.complaints set respondent_display_name = 'Deleted account' where respondent_id = p_user_id;
  update public.trip_ratings set rater_display_name = 'Deleted account' where rater_id = p_user_id;
  update public.trip_ratings set ratee_display_name = 'Deleted account' where ratee_id = p_user_id;
  update public.sos_reports set reporter_display_name = 'Deleted account' where reporter_id = p_user_id;
  update public.sos_reports s set driver_display_name = 'Deleted account'
    from public.trips t where t.id = s.trip_id and t.driver_id = p_user_id;
  update public.driver_app_feedback set driver_display_name = null
   where id in (select response_id from public.driver_feedback_obligations where driver_id = p_user_id);

  delete from auth.users where id = p_user_id;  -- cascades through profiles
  return v_files;
end;
$$;
