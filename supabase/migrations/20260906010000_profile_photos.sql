-- Profile photo: the repo's second Storage bucket, reusing the discount-ID
-- bucket's signed-URL, owner-prefixed-path shape exactly.
-- `profile_screen.dart`'s "Change photo" button currently says,
-- verbatim, "Photo change is a demo-only action." -- this migration is the
-- server-side half that makes it a real one.

-- ---------------------------------------------------------------------------
-- Storage: profile-photos, same signed-URL / owner-folder shape as
-- discount-eligibility-ids (20260905040000_fare_class_claims.sql). Not
-- public-read -- owner decision carried over from that spec, 5 Sep 2026.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', false)
on conflict (id) do nothing;

-- Deliberately no `alter table storage.objects enable row level security`
-- here -- 20260905040000_fare_class_claims.sql already established that
-- statement fails on the hosted project (`must be owner of table objects`,
-- storage.objects is owned by supabase_storage_admin there) and is only
-- needed for the local test shim, which already enables it once for the
-- whole schema in 00_bootstrap_local.sql.

create policy profile_photos_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy profile_photos_select_own_or_admin
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin((select auth.uid()))
    )
  );

-- No update/delete policy -- same idiom as the discount-eligibility bucket:
-- a new photo is a new path (the client timestamps the filename), and
-- profiles.avatar_path is simply repointed to it. The old object is
-- orphaned, not overwritten; cleaning up orphaned Storage objects is future
-- work, not a correctness requirement for this pass.

-- ---------------------------------------------------------------------------
-- profiles.avatar_path -- a Storage path, never a URL
-- ---------------------------------------------------------------------------
-- Client-writable directly (no RPC), like display_name/phone already are:
-- it is not one of the privileged columns guard_profiles_privileged_columns()
-- protects (role, status, is_internal_tester), so it belongs in the same
-- low-risk category. The security boundary is not this grant -- it is the
-- Storage RLS above, which decides who may actually mint a signed URL for
-- whatever path this column names, exactly the same "defense in depth, not
-- the real gate" relationship submit_fare_class_claim's photo-path check
-- has to discount_id_insert_own. The check constraint below is the direct
-- update's equivalent of that defense-in-depth check (there is no RPC body
-- here to put it in).
alter table public.profiles
  add column if not exists avatar_path text;

alter table public.profiles
  add constraint profiles_avatar_path_own_folder
  check (avatar_path is null or avatar_path like (id::text || '/%'));

comment on column public.profiles.avatar_path is
  'Storage path into the profile-photos bucket, not a URL -- every read '
  'mints a short-lived signed URL client-side. Client-writable directly '
  '(see the update grant below and profiles_avatar_path_own_folder), '
  'because Storage''s own RLS -- not this column -- decides who may '
  'actually read whatever path is named here.';

grant update (avatar_path) on public.profiles to authenticated;
