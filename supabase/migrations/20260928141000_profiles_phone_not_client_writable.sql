-- A signed-in user could change profiles.phone with a direct update, skipping
-- OTP: phone_verified_at stayed set, trip counterparts saw the unproven number
-- (trip_counterpart_phone), and the number's real owner could no longer sign
-- up with it (profiles_phone_key). No client writes phone directly -- signup
-- sets it in handle_new_user and admins use SECURITY DEFINER RPCs -- so the
-- column grant is simply withdrawn. Found by the security audit, 28 Sep 2026.
-- Regression: supabase/tests/84_profiles_phone_not_client_writable_test.sql.
revoke update (phone) on public.profiles from authenticated;
