-- An administrator can delete a rejected discount claim, with its ID photo.
--
-- A rejected claim is finished: the commuter files a fresh one with a new
-- photo, and until now the rejected row and its photo of an ID were kept for
-- nothing. Pending and approved claims stay undeletable -- one is still owed
-- a decision, the other is the record behind a discounted fare.
--
-- Storage objects cannot be deleted from SQL, so the console removes the
-- photo first and then calls delete_fare_class_claim(), which refuses while
-- the photo is still stored. Row first would strand the photo:
-- delete_account() finds a commuter's ID photos through these rows.

-- True only when at least one claim points at the photo and every claim that
-- does is rejected (bool_and over no rows is null, which a policy treats as
-- false).
create policy discount_id_delete_rejected_by_admin
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'discount-eligibility-ids'
    and public.is_admin((select auth.uid()))
    and (
      select bool_and(claim.status = 'rejected')
        from public.fare_class_claims claim
       where claim.id_photo_path = objects.name
    )
  );

create or replace function public.delete_fare_class_claim(p_claim_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.fare_class_claims%rowtype;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an administrator can delete a fare-class claim'
      using errcode = '42501';
  end if;

  select * into v_claim from public.fare_class_claims where id = p_claim_id for update;
  if not found then
    raise exception 'the claim does not exist' using errcode = 'P0002';
  end if;
  if v_claim.status <> 'rejected' then
    raise exception 'only a rejected claim can be deleted' using errcode = '22023';
  end if;

  if exists (
    select 1 from storage.objects
     where bucket_id = 'discount-eligibility-ids'
       and name = v_claim.id_photo_path
  ) then
    raise exception 'remove the ID photo before deleting the claim'
      using errcode = '55000';
  end if;

  delete from public.fare_class_claims where id = p_claim_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    auth.uid(),
    'fare_class_claim.deleted',
    v_claim.profile_id,
    jsonb_build_object('claim_id', v_claim.id, 'requested_class', v_claim.requested_class)
  );
end;
$$;

comment on function public.delete_fare_class_claim(uuid) is
  'Admin-only. Deletes a rejected claim once its ID photo is gone from '
  'Storage, and writes one admin_audit_logs row. Pending and approved claims '
  'are refused.';

revoke execute on function public.delete_fare_class_claim(uuid)
  from public, anon, authenticated;
grant execute on function public.delete_fare_class_claim(uuid)
  to authenticated, service_role;
