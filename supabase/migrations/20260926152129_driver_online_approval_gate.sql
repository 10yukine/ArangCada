-- The owner-only testing exception is server-managed app metadata, never
-- client-editable user metadata. Suspension and expiry still apply.
update auth.users u
set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
    || '{"driver_approval_test_bypass": true}'::jsonb
where lower(u.email) = 'tester@example.test'
  and exists (select 1 from public.profiles p
              where p.id = u.id and p.is_internal_tester and p.role = 'driver');

create or replace function public.can_driver_go_online(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.driver_profiles d
    join public.profiles p on p.id = d.id
    join auth.users u on u.id = p.id
    where d.id = p_uid and p.role = 'driver' and p.status = 'active'
      and (d.license_expires_on is null or d.license_expires_on >= current_date)
      and (p.phone_verified_at is not null or p.is_internal_tester)
      and (
        (p.is_internal_tester and
         u.raw_app_meta_data ->> 'driver_approval_test_bypass' = 'true')
        or (
          d.verification_status = 'approved'
          and not exists (
            select 1 from unnest(public.driver_required_document_types()) required(document_type)
            where not exists (
              select 1 from public.driver_documents doc
              where doc.driver_id = d.id and doc.document_type = required.document_type
                and doc.status = 'approved'
            )
          )
        )
      )
  );
$$;

-- Withdraw availability immediately when a required document is removed or
-- replaced pending review. Dispatch also rechecks can_driver_go_online.
create or replace function public.enforce_driver_document_availability()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_driver uuid;
begin
  if TG_OP = 'DELETE' then v_driver := OLD.driver_id;
  else v_driver := NEW.driver_id;
  end if;
  update public.driver_availability set is_online = false, updated_at = now()
  where driver_id = v_driver and is_online
    and not public.can_driver_go_online(v_driver);
  return null;
end;
$$;
revoke all on function public.enforce_driver_document_availability() from public;
create trigger driver_document_availability
  after insert or update or delete on public.driver_documents
  for each row execute function public.enforce_driver_document_availability();

update public.driver_availability set is_online = false, updated_at = now()
where is_online and not public.can_driver_go_online(driver_id);

create or replace function public.admin_review_driver(
  p_driver_id uuid,
  p_decision  text,
  p_reason    text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth.uid();
  v_status     public.driver_verification_status;
  v_unapproved integer;
begin
  if not public.is_admin(v_actor) then
    raise exception 'admin_review_driver: admin privileges required'
      using errcode = '42501';
  end if;

  if p_decision is distinct from 'approve' then
    raise exception 'admin_review_driver: enrolled drivers may only be approved; use suspension to restrict access'
      using errcode = '22023';
  end if;

  select verification_status into v_status
    from public.driver_profiles where id = p_driver_id;

  if not found then
    raise exception 'admin_review_driver: no such driver' using errcode = 'P0002';
  end if;

  select count(*)
    into v_unapproved
    from unnest(public.driver_required_document_types()) as t(dt)
   where not exists (
           select 1
             from public.driver_documents d
            where d.driver_id     = p_driver_id
              and d.document_type = t.dt
              and d.status        = 'approved'
         );

  if v_unapproved > 0 then
    raise exception 'admin_review_driver: % required document(s) are missing or not yet approved', v_unapproved
      using errcode = '22023';
  end if;

  update public.driver_profiles
     set verification_status = 'approved',
         rejection_reason    = null,
         reviewed_by         = v_actor,
         reviewed_at         = now(),
         updated_at          = now()
   where id = p_driver_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (v_actor, 'driver.approve', p_driver_id, p_reason);
end;
$$;

comment on function public.admin_review_driver(uuid, text, text) is
  'Approve an enrolled driver. Approval re-checks that every required document '
  'exists and is itself approved, rather than trusting the reviewer.';

revoke execute on function public.admin_review_driver(uuid, text, text) from anon;
