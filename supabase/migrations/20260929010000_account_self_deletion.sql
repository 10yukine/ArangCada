-- Self-service account deletion (Google Play account-deletion requirement).
--
-- Replaces 20260928180000's email-confirmed request queue, which only told a
-- privacy officer to delete the account by hand. Now the account is deleted
-- on the spot: supabase/functions/account-deletion checks a fresh password
-- sign-in, calls delete_account(), then removes the returned Storage files.
--
-- What goes and what stays follows Privacy Policy section 8:
--   * deleted: the Auth user, profile, push tokens, driver record/documents/
--     availability, discount claims, share links, the user's chat messages and
--     voice notes, and pending driver-feedback obligations;
--   * kept, de-identified: trips, ratings, complaints, SOS reports, reported
--     chats, trip events and audit logs (research + LGU incident records).
--     Their link to the account becomes NULL and every copied name becomes
--     'Deleted account'.
--
-- Administrators are removed from the admin console, not here; demo accounts
-- are shared fixtures; nobody can delete mid-ride.

drop table if exists public.account_deletion_requests;  -- 0 rows when replaced

-- Kept records lose their link to the deleted account.
alter table public.trips alter column rider_id drop not null;
alter table public.trips
  drop constraint trips_rider_id_fkey,
  add constraint trips_rider_id_fkey foreign key (rider_id) references public.profiles (id) on delete set null,
  drop constraint trips_driver_id_fkey,
  add constraint trips_driver_id_fkey foreign key (driver_id) references public.profiles (id) on delete set null,
  -- A deleted driver leaves closed trips driverless; live trips still need one
  -- (and delete_account refuses anyone on a live trip).
  drop constraint trips_driver_required_after_assignment,
  add constraint trips_driver_required_after_assignment check (
    status in ('requested', 'searching_driver', 'cancelled_by_rider', 'no_driver_available',
               'completed', 'cancelled_by_driver')
    or driver_id is not null
  );

alter table public.complaints
  alter column complainant_id drop not null,
  alter column respondent_id drop not null,
  drop constraint complaints_complainant_id_fkey,
  add constraint complaints_complainant_id_fkey foreign key (complainant_id) references public.profiles (id) on delete set null,
  drop constraint complaints_respondent_id_fkey,
  add constraint complaints_respondent_id_fkey foreign key (respondent_id) references public.profiles (id) on delete set null;

alter table public.sos_reports
  alter column reporter_id drop not null,
  drop constraint sos_reports_reporter_id_fkey,
  add constraint sos_reports_reporter_id_fkey foreign key (reporter_id) references public.profiles (id) on delete set null;

alter table public.reported_trip_chats
  alter column reporter_id drop not null,
  drop constraint reported_trip_chats_reporter_id_fkey,
  add constraint reported_trip_chats_reporter_id_fkey foreign key (reporter_id) references public.profiles (id) on delete set null;

alter table public.trip_ratings
  alter column rater_id drop not null,
  alter column ratee_id drop not null,
  drop constraint trip_ratings_rater_id_fkey,
  add constraint trip_ratings_rater_id_fkey foreign key (rater_id) references public.profiles (id) on delete set null,
  drop constraint trip_ratings_ratee_id_fkey,
  add constraint trip_ratings_ratee_id_fkey foreign key (ratee_id) references public.profiles (id) on delete set null;

alter table public.trip_events
  drop constraint trip_events_actor_id_fkey,
  add constraint trip_events_actor_id_fkey foreign key (actor_id) references public.profiles (id) on delete set null;

-- Some user actions (claims, complaints) are audit-logged with the user as actor.
alter table public.admin_audit_logs
  alter column actor_id drop not null,
  drop constraint admin_audit_logs_actor_id_fkey,
  add constraint admin_audit_logs_actor_id_fkey foreign key (actor_id) references public.profiles (id) on delete set null,
  drop constraint admin_audit_logs_target_profile_id_fkey,
  add constraint admin_audit_logs_target_profile_id_fkey foreign key (target_profile_id) references public.profiles (id) on delete set null;

alter table public.admin_invites
  drop constraint admin_invites_accepted_user_id_fkey,
  add constraint admin_invites_accepted_user_id_fkey foreign key (accepted_user_id) references public.profiles (id) on delete set null;
alter table public.driver_invites
  drop constraint driver_invites_accepted_user_id_fkey,
  add constraint driver_invites_accepted_user_id_fkey foreign key (accepted_user_id) references public.profiles (id) on delete set null;

-- The user's own personal rows go with the account.
alter table public.fare_class_claims
  drop constraint fare_class_claims_profile_id_fkey,
  add constraint fare_class_claims_profile_id_fkey foreign key (profile_id) references public.profiles (id) on delete cascade;
alter table public.ride_share_links
  drop constraint ride_share_links_created_by_fkey,
  add constraint ride_share_links_created_by_fkey foreign key (created_by) references public.profiles (id) on delete cascade;
alter table public.trip_messages
  drop constraint trip_messages_sender_id_fkey,
  add constraint trip_messages_sender_id_fkey foreign key (sender_id) references public.profiles (id) on delete cascade;
alter table public.driver_feedback_obligations
  drop constraint driver_feedback_obligations_driver_id_fkey,
  add constraint driver_feedback_obligations_driver_id_fkey foreign key (driver_id) references public.driver_profiles (id) on delete cascade;

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
    raise exception 'Administrator accounts are removed from the admin console.'
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

comment on function public.delete_account(uuid) is
  'Deletes an account and its personal data, de-identifying retained records. '
  'Called only by the account-deletion edge function after a fresh password sign-in.';

revoke execute on function public.delete_account(uuid) from public, anon, authenticated;
grant execute on function public.delete_account(uuid) to service_role;
