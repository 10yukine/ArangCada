-- Fix: update_complaint_status() locked out every TODA-scoped admin.
--
-- Independent review finding (Copilot, PR #17 council-review snapshot,
-- 6 Sep 2026): the SECURITY DEFINER function gated only on
-- is_admin(auth.uid()), which -- per its own definition in
-- 20260825133421_live_connected_vertical_slice.sql -- explicitly EXCLUDES
-- any admin who has a TODA scope assigned ("A TODA assignment explicitly
-- removes that account from every existing global policy."). That is the
-- opposite of a privilege-escalation risk: it made update_complaint_status()
-- MORE restrictive than the table's own RLS SELECT policy
-- (complaints_select_complainant_or_scoped_admin, same migration), which
-- already grants read access to a TODA-scoped admin via has_admin_scope().
-- A TODA admin could see their own zone's complaints and never act on one.
--
-- 20260905020000_complaints.sql's own header says this function is
-- "modelled line-for-line on ... update_sos_status()" -- true, but
-- update_sos_status() (20260825170000) has the identical is_admin()-only
-- gate, so the mirroring faithfully copied a gap rather than the
-- has_admin_scope() + toda_zone_id pattern used everywhere admin action
-- (not just admin read) is meant to be TODA-scoped, e.g.
-- review_driver_application() at 20260825170000:385-398. Whether
-- update_sos_status() should get the same fix is a separate decision
-- (SOS may be deliberately LGU-only-escalation by design, not yet
-- confirmed) and is out of scope here -- this migration only touches
-- update_complaint_status(), the function actually flagged.

create or replace function public.update_complaint_status(
  p_complaint_id uuid,
  p_status text,
  p_note text
)
returns public.complaints
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_complaint public.complaints%rowtype;
begin
  select * into v_complaint from public.complaints where id = p_complaint_id for update;
  if not found or not public.has_admin_scope(auth.uid(), v_complaint.toda_zone_id) then
    raise exception 'complaint review is restricted to the assigned TODA or LGU'
      using errcode = '42501';
  end if;

  if p_status not in ('acknowledged', 'investigating', 'resolved', 'dismissed') then
    raise exception 'unknown complaint status'
      using errcode = '22023';
  end if;

  if v_complaint.status in ('resolved', 'dismissed') and v_complaint.status <> p_status then
    raise exception 'a closed complaint cannot be reopened through this action'
      using errcode = '22023';
  end if;

  update public.complaints
     set status = p_status,
         admin_note = nullif(trim(coalesce(p_note, '')), ''),
         updated_at = now()
   where id = p_complaint_id
   returning * into v_complaint;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    auth.uid(),
    'complaint.' || p_status,
    v_complaint.respondent_id,
    jsonb_build_object('complaint_id', v_complaint.id, 'trip_id', v_complaint.trip_id)
  );

  return v_complaint;
end;
$$;

comment on function public.update_complaint_status(uuid, text, text) is
  'TODA-scoped-or-LGU-admin status transition on a complaint, matching the '
  'has_admin_scope() read policy on this table. Writes one admin_audit_logs '
  'row per change. Fixed 6 Sep 2026 (later still): originally gated on the '
  'global-only is_admin(), which locked out every TODA-scoped admin -- see '
  'this migration''s header.';

-- Grants are unchanged (already authenticated/service_role from
-- 20260905020000_complaints.sql); create or replace does not reset them,
-- but restate for clarity and to survive a future drop/recreate.
revoke execute on function public.update_complaint_status(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.update_complaint_status(uuid, text, text)
  to authenticated, service_role;
