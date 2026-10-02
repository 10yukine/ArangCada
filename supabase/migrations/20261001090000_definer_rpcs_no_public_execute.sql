-- Take PUBLIC's EXECUTE off five SECURITY DEFINER functions (security audit, 1 Oct 2026).
--
-- Their migrations revoked EXECUTE from anon (and authenticated for the two
-- finalize functions) but not from PUBLIC, so anon kept it through PUBLIC: the
-- hosted project's advisor lists all five as callable without signing in. Each
-- body rejects such a caller (service_role check, or an active-admin check), so
-- nothing was exposed -- but the grant is described in those migrations as the
-- primary control, and it was not doing anything.
--
-- The explicit grants stay as they are: service_role for the finalize functions,
-- authenticated and service_role for the three admin functions.
--
-- Regression: supabase/tests/89_audit_run2_followups_test.sql.
revoke execute on function public.admin_finalize_invited_account(text, uuid, text, text) from public;
revoke execute on function public.driver_finalize_invited_account(text, uuid) from public;
revoke execute on function public.admin_list_drivers() from public;
revoke execute on function public.admin_update_driver_name(uuid, text, text, text) from public;
revoke execute on function public.admin_update_driver_record(uuid, text, text, text, text, uuid, date) from public;
