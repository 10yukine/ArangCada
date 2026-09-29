-- Close a live Supabase Security Advisor finding on the hosted project:
--
--   "Public Can Execute SECURITY DEFINER Function"       (anon)
--   "Signed-In Users Can Execute SECURITY DEFINER Function" (authenticated)
--
-- Entity: public.rls_auto_enable()
--
-- public.rls_auto_enable() is SECURITY DEFINER and, at audit time, was
-- callable by both `anon` and `authenticated` via PostgREST
-- (POST /rest/v1/rpc/rls_auto_enable). A SECURITY DEFINER function runs with
-- the privileges of its owner rather than the caller, so an unauthenticated
-- or merely-authenticated request could trigger owner-level behaviour --
-- exactly the combination this project's RLS work exists to prevent.
--
-- IMPORTANT: this function is NOT defined anywhere in this repo's tracked
-- migrations, seed data, or tests. It exists on the live hosted project but
-- was created outside the migration-file workflow this repo otherwise uses
-- -- most likely directly through the Supabase Dashboard SQL editor, or an
-- MCP tool call made against the remote project without the corresponding
-- file being written back to supabase/migrations/. That is schema drift: the
-- hosted project's schema is not fully reconstructable from this repo alone,
-- which is exactly the gap the migrations-tracked-in-git discipline
-- exists to close. Worth finding out how it got there before it happens again.
--
-- This migration does not attempt to recreate the function -- no agent in
-- this repo has ever read its actual definition -- only to close the public-
-- exposure hole, and to make that closure itself tracked in version control
-- rather than living only in the dashboard. It leaves SECURITY DEFINER and
-- any grant to postgres/service_role untouched, since revoking only from
-- anon/authenticated/public fully closes both flagged lint items without
-- guessing at whether some legitimate elevated caller still needs it.
--
-- Guarded with to_regprocedure() so this is a safe no-op everywhere the
-- function does not exist -- every local/WSL test database today -- and only
-- takes effect on the one hosted project where it is actually present.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end
$$;
