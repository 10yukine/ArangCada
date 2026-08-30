-- Security hardening: remove unauthenticated RPC execution and pin helper paths.
-- spatial_ref_sys RLS and PostGIS placement intentionally remain unchanged;
-- both require a separate policy/compatibility review.

alter function public.fare_km_increments(integer) set search_path = public;
alter function public.fare_chargeable_km(integer, integer) set search_path = public;
alter function public.compute_fare(integer, public.ride_type, public.passenger_fare_class, integer) set search_path = public;
alter function public.normalize_ph_mobile(text) set search_path = public;
alter function public.guard_profiles_privileged_columns() set search_path = public;
alter function public.driver_required_document_types() set search_path = public;
alter function public.mask_name(text) set search_path = public;

revoke execute on function public.accept_ride(uuid) from anon;
revoke execute on function public.admin_activate_new_driver(uuid, uuid, uuid, text, text) from anon;
revoke execute on function public.admin_demote_driver(uuid, text) from anon;
revoke execute on function public.admin_preview_driver_candidate(text, text) from anon;
revoke execute on function public.admin_promote_commuter_to_driver(text, text, text, text, uuid, text, text) from anon;
revoke execute on function public.admin_review_driver(uuid, text, text) from anon;
revoke execute on function public.admin_set_profile_status(uuid, public.profile_status, text) from anon;
revoke execute on function public.can_driver_go_online(uuid) from anon;
revoke execute on function public.cancel_ride(uuid) from anon;
revoke execute on function public.complete_trip(uuid) from anon;
revoke execute on function public.compute_fare_centavos(integer, public.ride_type, public.passenger_fare_class, integer) from anon;
revoke execute on function public.compute_fare_unit_centavos(integer, public.ride_type, public.passenger_fare_class) from anon;
revoke execute on function public.create_driver_record(uuid, uuid, uuid, text, text, text) from anon;
revoke execute on function public.decline_ride(uuid) from anon;
revoke execute on function public.driver_documents_check_completion() from anon;
revoke execute on function public.driver_requirements_status(uuid) from anon;
revoke execute on function public.expire_ride(uuid) from anon;
revoke execute on function public.get_admin_scope() from anon;
revoke execute on function public.get_driver_feedback_state() from anon;
revoke execute on function public.get_feedback_settings() from anon;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.has_admin_scope(uuid, uuid) from anon;
revoke execute on function public.is_admin(uuid) from anon;
revoke execute on function public.is_point_in_toda_zone(uuid, double precision, double precision) from anon;
revoke execute on function public.mark_arrived(uuid) from anon;
revoke execute on function public.publish_driver_location(uuid, double precision, double precision, double precision) from anon;
revoke execute on function public.request_ride(double precision, double precision, double precision, double precision, text, text, text) from anon;
revoke execute on function public.set_driver_availability(boolean, double precision, double precision) from anon;
revoke execute on function public.st_estimatedextent(text, text) from anon;
revoke execute on function public.st_estimatedextent(text, text, text) from anon;
revoke execute on function public.st_estimatedextent(text, text, text, boolean) from anon;
revoke execute on function public.start_trip(uuid) from anon;
revoke execute on function public.sync_profile_email() from anon;
revoke execute on function public.toda_zone_covering(double precision, double precision) from anon;
revoke execute on function public.update_feedback_settings(integer, integer, boolean) from anon;
