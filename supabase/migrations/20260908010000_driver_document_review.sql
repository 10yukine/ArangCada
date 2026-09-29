-- Driver verification redesign: a real Storage bucket for driver_documents
-- (none has ever existed), audited admin upload/review RPCs, and a
-- TODA-scoped write boundary matching admin_review_scoped_driver's own
-- shape.
--
-- WHY THIS EXISTS
--
-- driver_documents (table, 20260728090400) has never had a Storage bucket,
-- and driver_documents_admin_all grants blanket insert/update/delete with
-- no RPC and no admin_audit_logs entry -- unlike every other admin
-- decision path in this schema (complaints, ratings, fare-class claims,
-- driver applications), which write only through a security definer RPC
-- specifically so the audit trail cannot be bypassed. Found during a
-- driver-verification redesign, 8 Sep 2026.

-- ---------------------------------------------------------------------------
-- Storage: driver-documents, same private/signed-URL shape as
-- discount-eligibility-ids and profile-photos.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do nothing;

-- Path convention: {driver_id}/{document_type}-{timestamp}.{ext}. The admin
-- is not the file owner (the driver is), so unlike profile-photos this is
-- not an owner-prefixed-path check on the writer -- any admin may insert
-- under any driver's folder, matching driver_documents_admin_all's own
-- existing (unchanged) blanket admin scope on the table's SELECT side.
create policy driver_documents_photos_insert_admin
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'driver-documents'
    and public.is_admin((select auth.uid()))
  );

-- Owner-or-admin read, identical shape to profile_photos_select_own_or_admin
-- -- no mobile UI reads this yet, but the policy is correct in advance for
-- a future driver-side "my documents" viewer at zero extra cost now.
create policy driver_documents_photos_select_own_or_admin
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'driver-documents'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin((select auth.uid()))
    )
  );

-- No update/delete policy -- a replacement is a new path (client
-- timestamps the filename), not an overwrite, same idiom as the other two
-- buckets. The old object is orphaned, not cleaned up; same as those two.

-- ---------------------------------------------------------------------------
-- Narrow driver_documents_admin_all from `for all` to `for select` --
-- writes now go exclusively through the two RPCs below, matching the
-- audited-write convention every other admin table already follows.
-- driver_documents_select_own / driver_documents_insert_own (the driver's
-- own future self-upload path) are untouched.
-- ---------------------------------------------------------------------------
drop policy driver_documents_admin_all on public.driver_documents;

-- TODA-scoped, not the plain is_admin() this migration first shipped with
-- locally -- caught by 76_driver_document_review_test.sql before this ever
-- reached the hosted project. is_admin() alone excludes any admin who has
-- a TODA scope row (see admin_scopes' own definition), which would have
-- locked every TODA-scoped admin out of seeing driver_documents at all --
-- the exact same bug class already found and fixed once for
-- update_complaint_status() in 20260906020000_complaint_status_admin_scope.sql.
--
-- The scalar subquery (not a join/exists) is deliberate: a driver_documents
-- row can outlive or precede its driver_profiles row (driver_documents.driver_id
-- references profiles directly, not driver_profiles -- 40_rls_test.sql's own
-- fixture exercises exactly this, a document with no driver_profiles row at
-- all). When it returns NULL, has_admin_scope(uid, NULL) reduces to plain
-- is_admin(uid) -- has_admin_scope's own OR-exists clause can never match a
-- NULL toda_zone_id -- so an unscoped LGU admin still sees it and a
-- TODA-scoped one correctly does not (no zone to match against yet).
create policy driver_documents_select_admin
  on public.driver_documents for select
  to authenticated
  using (
    public.has_admin_scope(
      (select auth.uid()),
      (select dp.toda_zone_id from public.driver_profiles dp
        where dp.id = driver_documents.driver_id)
    )
  );

-- ---------------------------------------------------------------------------
-- admin_upsert_driver_document(): upload (or replace) a document on a
-- driver's behalf. TODA-scoped, same shape as admin_review_scoped_driver.
-- Always resets to 'pending' -- a fresh file needs a fresh review, per the
-- owner's confirmed "replace and reset" decision (not versioned history).
-- ---------------------------------------------------------------------------
create or replace function public.admin_upsert_driver_document(
  p_driver_id uuid,
  p_document_type public.document_type,
  p_storage_path text
)
returns public.driver_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.driver_profiles%rowtype;
  v_document public.driver_documents%rowtype;
begin
  select * into v_driver from public.driver_profiles where id = p_driver_id;
  if not found or not public.has_admin_scope((select auth.uid()), v_driver.toda_zone_id) then
    raise exception 'driver document upload is restricted to the assigned TODA or LGU'
      using errcode = '42501';
  end if;

  insert into public.driver_documents (driver_id, document_type, storage_path, status)
  values (p_driver_id, p_document_type, p_storage_path, 'pending')
  on conflict (driver_id, document_type) do update
    set storage_path = excluded.storage_path,
        status = 'pending',
        reviewed_by = null,
        reviewed_at = null,
        rejection_reason = null
  returning * into v_document;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    (select auth.uid()),
    'driver_document.uploaded',
    p_driver_id,
    jsonb_build_object('document_id', v_document.id, 'document_type', p_document_type)
  );

  return v_document;
end;
$$;

comment on function public.admin_upsert_driver_document(uuid, public.document_type, text) is
  'Admin uploads (or replaces) a driver''s document on their behalf -- the '
  'one place driver_documents.storage_path is written, so an audit row is '
  'unavoidable. Always resets status to pending; see this migration''s '
  'header for why replace-and-reset was chosen over versioned history.';

revoke execute on function public.admin_upsert_driver_document(uuid, public.document_type, text)
  from public, anon;
grant execute on function public.admin_upsert_driver_document(uuid, public.document_type, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- admin_review_driver_document(): approve/reject one already-uploaded
-- document. TODA-scoped, same shape as admin_review_scoped_driver.
-- ---------------------------------------------------------------------------
create or replace function public.admin_review_driver_document(
  p_document_id uuid,
  p_approve boolean,
  p_rejection_reason text
)
returns public.driver_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_document public.driver_documents%rowtype;
  v_driver public.driver_profiles%rowtype;
  v_status public.verification_status;
begin
  select * into v_document from public.driver_documents where id = p_document_id for update;
  if not found then
    raise exception 'the document does not exist'
      using errcode = 'P0002';
  end if;

  select * into v_driver from public.driver_profiles where id = v_document.driver_id;
  if not found or not public.has_admin_scope((select auth.uid()), v_driver.toda_zone_id) then
    raise exception 'driver document review is restricted to the assigned TODA or LGU'
      using errcode = '42501';
  end if;

  v_status := case when p_approve then 'approved' else 'rejected' end;
  if not p_approve and coalesce(trim(p_rejection_reason), '') = '' then
    raise exception 'a rejection reason is required'
      using errcode = '22023';
  end if;

  update public.driver_documents
     set status = v_status,
         reviewed_by = (select auth.uid()),
         reviewed_at = now(),
         rejection_reason = case when p_approve then null else trim(p_rejection_reason) end
   where id = p_document_id
   returning * into v_document;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    (select auth.uid()),
    case when p_approve then 'driver_document.approved' else 'driver_document.rejected' end,
    v_document.driver_id,
    jsonb_build_object('document_id', v_document.id, 'document_type', v_document.document_type)
  );

  return v_document;
end;
$$;

comment on function public.admin_review_driver_document(uuid, boolean, text) is
  'Admin approves or rejects one already-uploaded driver document. '
  'TODA-scoped, matching admin_review_scoped_driver''s own gate -- an '
  'admin who can review the driver overall can review their individual '
  'documents too.';

revoke execute on function public.admin_review_driver_document(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_review_driver_document(uuid, boolean, text)
  to authenticated, service_role;
