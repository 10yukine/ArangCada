-- Close two direct-write paths no client uses (security audit, 28 Sep 2026).
--
-- driver_documents: drivers are invite-only and their documents are recorded by
-- admins through admin_upsert_driver_document (SECURITY DEFINER). The leftover
-- insert policy let a driver insert their own rows already marked 'approved',
-- skipping the per-document review.
--
-- ride_share_links: links are created by create_ride_share_link, which checks
-- the caller is the trip's rider. The leftover update policy let a link owner
-- repoint trip_id at another rider's trip and publish its live location.
--
-- Regression: supabase/tests/85_audit_followups_test.sql.
drop policy if exists driver_documents_insert_own on public.driver_documents;
revoke insert on public.driver_documents from anon, authenticated;

drop policy if exists ride_share_links_update_own on public.ride_share_links;
revoke update on public.ride_share_links from anon, authenticated;
