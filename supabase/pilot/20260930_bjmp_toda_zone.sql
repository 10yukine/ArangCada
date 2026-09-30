-- Pilot TODA zone: BJMP TODA, Turbina, Calamba City. Applied to the live
-- project by hand on 2026-09-30; not a migration, because the database tests
-- still rely on the seeded placeholder zones.
--
-- The TODA's real operating area is not known yet, so the zone is all of
-- Calamba (OpenStreetMap relation 1578579, (c) OpenStreetMap contributors,
-- ODbL, simplified to ~50 m). Dispatch's own radius keeps far pickups from
-- reaching Turbina drivers. Redraw it once the TODA confirms its boundary.
-- Terminal: plus code 7Q6354MP+JHC, Turbina Purok-2 at the Maharlika Highway.
--
-- Everything that pointed at the old placeholder zones moves to BJMP TODA,
-- then the placeholders are deleted.
do $$
declare
  v_zone uuid;
  v_fake uuid[];
begin
  insert into public.toda_zones (code, name, barangay, boundary, terminal_point)
  values (
    'CAL-TUR-BJMP',
    'BJMP TODA',
    'Turbina',
    public.st_geomfromtext('SRID=4326;POLYGON((121.01982 14.16743, 121.02366 14.16233, 121.02378 14.15581,
    121.02720 14.15192, 121.02800 14.15220, 121.02838 14.15396,
    121.03021 14.15471, 121.03130 14.15374, 121.03418 14.15331,
    121.03733 14.15383, 121.03749 14.15229, 121.03933 14.15216,
    121.03905 14.15122, 121.04072 14.15210, 121.04328 14.15548,
    121.04596 14.15695, 121.04780 14.15311, 121.04906 14.15414,
    121.04984 14.15123, 121.05770 14.15323, 121.06976 14.15448,
    121.09834 14.15610, 121.10342 14.15484, 121.10304 14.15413,
    121.10863 14.15203, 121.11026 14.15268, 121.11033 14.15180,
    121.11476 14.15044, 121.11632 14.14804, 121.11536 14.14677,
    121.11651 14.14477, 121.11890 14.14530, 121.12467 14.14390,
    121.12737 14.14540, 121.12844 14.14734, 121.13035 14.14483,
    121.13062 14.14290, 121.13342 14.14174, 121.13537 14.14214,
    121.13666 14.14436, 121.13989 14.14437, 121.14033 14.14352,
    121.14059 14.14434, 121.14108 14.14368, 121.14186 14.14413,
    121.15210 14.14209, 121.15453 14.14269, 121.15677 14.14090,
    121.15872 14.14126, 121.16034 14.14057, 121.16180 14.14129,
    121.17134 14.13770, 121.18302 14.15180, 121.19992 14.16644,
    121.20356 14.17947, 121.20257 14.17941, 121.20465 14.18462,
    121.20371 14.18577, 121.22143 14.25690, 121.21267 14.26139,
    121.20752 14.26621, 121.16803 14.23526, 121.16138 14.23427,
    121.16016 14.23513, 121.15654 14.23316, 121.15512 14.23373,
    121.15365 14.23219, 121.15198 14.23269, 121.14986 14.23219,
    121.13490 14.22487, 121.13375 14.22574, 121.13499 14.22981,
    121.13043 14.23244, 121.12993 14.23444, 121.12104 14.23422,
    121.11880 14.23485, 121.11823 14.23712, 121.11519 14.23757,
    121.11344 14.23683, 121.11263 14.23439, 121.10649 14.23139,
    121.10543 14.22996, 121.10340 14.22983, 121.10041 14.22821,
    121.09551 14.22835, 121.09352 14.22670, 121.08988 14.22705,
    121.08876 14.22430, 121.08362 14.22326, 121.08282 14.22188,
    121.07675 14.21836, 121.07259 14.21838, 121.07162 14.21751,
    121.06791 14.21777, 121.06620 14.21582, 121.06217 14.21438,
    121.06221 14.21349, 121.06009 14.21105, 121.05580 14.20885,
    121.05412 14.20420, 121.05138 14.20307, 121.05217 14.20263,
    121.05157 14.20170, 121.05305 14.20095, 121.05204 14.20011,
    121.05296 14.19969, 121.05022 14.19714, 121.05014 14.19564,
    121.04912 14.19543, 121.04922 14.19391, 121.04050 14.19235,
    121.03878 14.18875, 121.03609 14.18779, 121.03566 14.18519,
    121.03132 14.18046, 121.03221 14.17190, 121.02595 14.17231,
    121.02203 14.17122, 121.01982 14.16743))'),
    public.st_geomfromtext('SRID=4326;POINT(121.13639 14.18406)')
  )
  returning id into v_zone;

  select array_agg(id) into v_fake
    from public.toda_zones
   where code in ('CAL-POB-01', 'CAL-CAN-01', 'DEV-SJVTODA-CABUYAO');

  update public.admin_invites set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.admin_scopes set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.complaints set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.driver_app_feedback set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.driver_availability set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.driver_feedback_obligations set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.driver_invites set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.driver_profiles set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.sos_reports set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.toda_members set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.trip_ratings set toda_zone_id = v_zone where toda_zone_id = any(v_fake);
  update public.trips set toda_zone_id = v_zone where toda_zone_id = any(v_fake);

  delete from public.toda_zones where id = any(v_fake);
end
$$;
