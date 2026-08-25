-- Driver verification: the required-document list, its status, the go-online
-- gate, and the trigger that moves a driver into review.
--
-- Every function here is security definer with a pinned search_path, and every
-- one revokes execute from anon. Supabase (and supabase/tests/00_bootstrap_local.sql,
-- which mirrors it) grants execute on new functions to anon by default, so an
-- explicit revoke is required rather than optional.

-- ---------------------------------------------------------------------------
-- The required-document list
-- ---------------------------------------------------------------------------
-- PROVISIONAL. These four have NOT been confirmed against Calamba City's
-- actual MTOP franchise requirements -- see docs/CLIENT_MEETING_QUESTIONS.md
-- question B1 and .pipeline/specs.md §10 open question 1. Deliberately the
-- single place the list is defined: correcting it after the client meeting is
-- a one-line change here, with no other code touched.
--
-- barangay_clearance and vehicle_photo remain optional.
create or replace function public.driver_required_document_types()
returns public.document_type[]
language sql
immutable
as $$
  select array[
    'drivers_license',
    'mtop_franchise',
    'toda_membership',
    'or_cr'
  ]::public.document_type[];
$$;

comment on function public.driver_required_document_types() is
  'PROVISIONAL list of documents required before a driver may be approved. '
  'Unconfirmed against Calamba LGU requirements -- see '
  'docs/CLIENT_MEETING_QUESTIONS.md B1. Single source of truth: change here only.';

revoke execute on function public.driver_required_document_types() from anon;

-- ---------------------------------------------------------------------------
-- Per-document status, for the driver's own checklist
-- ---------------------------------------------------------------------------
-- Powers the "2 of 4 requirements submitted" banner. Guarded to self-or-admin:
-- which documents a person has filed is their business, and this function is
-- security definer precisely so it can read past driver_documents' RLS.
create or replace function public.driver_requirements_status(
  p_uid uuid default auth.uid()
)
returns table (
  required_type public.document_type,
  submitted     boolean,
  review_status public.verification_status
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_uid is null then
    raise exception 'driver_requirements_status: no authenticated user'
      using errcode = '28000';
  end if;

  if p_uid <> auth.uid() and not public.is_admin(auth.uid()) then
    raise exception 'driver_requirements_status: not permitted to read another user''s documents'
      using errcode = '42501';
  end if;

  return query
    select t.dt,
           (d.id is not null),
           d.status
      from unnest(public.driver_required_document_types()) as t(dt)
      left join public.driver_documents d
        on d.driver_id = p_uid
       and d.document_type = t.dt
     order by t.dt;
end;
$$;

comment on function public.driver_requirements_status(uuid) is
  'One row per required document type for the given driver, with whether it '
  'has been submitted and its review status. Self or admin only.';

revoke execute on function public.driver_requirements_status(uuid) from anon;

-- ---------------------------------------------------------------------------
-- The go-online gate
-- ---------------------------------------------------------------------------
-- The single authority on whether a driver may receive dispatch.
--
-- Licence expiry is enforced here rather than by an administrator noticing:
-- a driver whose licence lapses at midnight stops being dispatchable at
-- midnight, with no human in the loop. A null expiry never blocks anyone,
-- because whether the TODA tracks expiry at all is still unconfirmed
-- (docs/CLIENT_MEETING_QUESTIONS.md A7) and treating "unknown" as "expired"
-- would strand every driver onboarded before that answer arrives.
--
-- NOT guarded to self-or-admin, deliberately. Dispatch will need to ask this
-- about drivers other than the caller. The information it leaks -- whether a
-- given uuid is a dispatchable driver -- requires already knowing that uuid,
-- and no function in this migration set hands one out: admin_preview_driver_candidate
-- returns none by design.
create or replace function public.can_driver_go_online(
  p_uid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.driver_profiles d
      join public.profiles p on p.id = d.id
     where d.id = p_uid
       and d.verification_status = 'approved'
       and p.role   = 'driver'
       and p.status = 'active'
       and (d.license_expires_on is null or d.license_expires_on >= current_date)
  );
$$;

comment on function public.can_driver_go_online(uuid) is
  'True when the driver is approved, still role=driver, not suspended, and '
  'holds a licence that has not lapsed. The single go-online gate; when '
  'driver_availability and real dispatch are built, they consult this.';

revoke execute on function public.can_driver_go_online(uuid) from anon;

-- ---------------------------------------------------------------------------
-- Automatic move into review
-- ---------------------------------------------------------------------------
-- Documents are handed over face-to-face and uploaded by the administrator, so
-- there is no driver-side "submit" action to press and no
-- driver_submit_for_review() RPC. Completion is therefore observed rather than
-- declared: the moment the last required document exists, the driver moves to
-- pending_review.
--
-- The `and verification_status = 'unverified'` predicate makes this both
-- idempotent and one-way. Re-uploading a document for an already-approved
-- driver must not drag them backwards into review.
create or replace function public.driver_documents_check_completion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_missing integer;
begin
  select count(*)
    into v_missing
    from unnest(public.driver_required_document_types()) as t(dt)
   where not exists (
           select 1
             from public.driver_documents d
            where d.driver_id     = new.driver_id
              and d.document_type = t.dt
         );

  if v_missing = 0 then
    update public.driver_profiles
       set verification_status = 'pending_review',
           submitted_at        = coalesce(submitted_at, now()),
           updated_at          = now()
     where id = new.driver_id
       and verification_status = 'unverified';
  end if;

  return new;
end;
$$;

comment on function public.driver_documents_check_completion() is
  'Moves a driver from unverified to pending_review once every required '
  'document exists. Replaces the driver-side submit action, which has no '
  'caller under face-to-face onboarding.';

create trigger driver_documents_completion
  after insert or update on public.driver_documents
  for each row
  execute function public.driver_documents_check_completion();
