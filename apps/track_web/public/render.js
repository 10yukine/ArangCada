// Pure logic for the public ride-tracking page.
//
// Deliberately free of DOM and network access so it can be tested with
// `node --test` and no browser, no bundler, and no new dependency. Everything
// here takes data in and returns data out; track.js does the touching of
// elements and the fetching.
//
// PRIVACY CONSTRAINT, enforced by test:
// This module must never read a rider-identifying field from the payload.
// ride_share_view() does not return one, and if a future migration widens that
// payload, nothing here should start rendering it by accident.

/**
 * Pull the share token out of the URL.
 *
 * Two shapes are accepted:
 *   /t/<token>      the real one; wrangler's single-page-application routing
 *                   serves index.html for any path that is not a real file
 *   ?t=<token>      a fallback that works without that routing
 *
 * Returns null when there is no plausible token, so the caller can show the
 * expired state rather than firing a pointless request.
 */
export function parseToken(pathname, search) {
  const fromPath = /^\/t\/([A-Za-z0-9._-]+)\/?$/.exec(pathname || '');
  if (fromPath) return fromPath[1];

  const params = new URLSearchParams(search || '');
  const fromQuery = params.get('t');
  if (fromQuery && /^[A-Za-z0-9._-]+$/.test(fromQuery)) return fromQuery;

  return null;
}

/**
 * Human sentences for the trip statuses this page can encounter.
 *
 * Written for someone who has never used the app and does not know what
 * "driver_assigned" means. An unknown status must degrade to something
 * truthful rather than printing a raw enum at a worried parent -- a future
 * migration could add a status this page has never heard of.
 */
const STATUS_TEXT = {
  requested: 'Looking for a driver',
  searching_driver: 'Looking for a driver',
  driver_assigned: 'A driver has been assigned',
  accepted: 'The driver is on the way',
  driver_en_route: 'The driver is on the way',
  arrived: 'The driver has arrived at the pickup point',
  in_progress: 'The trip is in progress',
  emergency_reported: 'An emergency has been reported on this trip',
};

export function statusText(status) {
  if (!status) return 'Trip status unavailable';
  return STATUS_TEXT[status] || 'Trip in progress';
}

/** Emergency gets visual emphasis; everything else is neutral. */
export function statusTone(status) {
  return status === 'emergency_reported' ? 'alert' : 'normal';
}

/**
 * "just now" / "12s ago" / "5m ago" / "2h ago".
 *
 * Shown instead of an ETA. ride_share_view() does not return an ETA and the
 * page must not invent one -- a made-up arrival time is worse than no arrival
 * time to someone deciding whether to worry. Staleness is the honest signal:
 * it tells the viewer how much to trust the dot on the map.
 */
export function timeAgo(isoTimestamp, now = Date.now()) {
  if (!isoTimestamp) return 'no location yet';

  const then = Date.parse(isoTimestamp);
  if (Number.isNaN(then)) return 'no location yet';

  const seconds = Math.floor((now - then) / 1000);
  if (seconds < 0) return 'just now';
  if (seconds < 10) return 'just now';
  if (seconds < 60) return `${seconds}s ago`;

  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;

  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;

  return 'over a day ago';
}

/**
 * A position older than this is shown with a warning, because a stale dot
 * presented as current is actively misleading -- the viewer would think the
 * tricycle had stopped when really the phone lost signal.
 */
export const STALE_AFTER_SECONDS = 90;

export function isStale(isoTimestamp, now = Date.now()) {
  if (!isoTimestamp) return true;
  const then = Date.parse(isoTimestamp);
  if (Number.isNaN(then)) return true;
  return now - then > STALE_AFTER_SECONDS * 1000;
}

/**
 * Turn the RPC response into a view model.
 *
 * ride_share_view() returns a one-row array, or an EMPTY ARRAY when the token
 * is unknown, revoked, or the trip has ended. Empty is the expiry signal and it
 * is decided server-side; this function only reports it.
 *
 * All three of those cases collapse to the same view deliberately. A stranger
 * who guesses a token must not be able to tell "no such trip" from "that trip
 * finished" -- distinguishing them would confirm a token was once real.
 */
export function toViewModel(rows, now = Date.now()) {
  if (!Array.isArray(rows) || rows.length === 0) {
    return { kind: 'expired' };
  }

  const row = rows[0];

  const hasDriverPosition =
    typeof row.driver_lat === 'number' && typeof row.driver_lng === 'number';

  return {
    kind: 'active',
    status: row.status,
    statusText: statusText(row.status),
    statusTone: statusTone(row.status),

    // Place labels, not the rider. The commuter is never named on this page.
    pickupLabel: row.pickup_label || 'Pickup',
    destinationLabel: row.destination_label || 'Destination',

    driverName: row.driver_display_name || 'Driver not yet assigned',
    bodyNumber: row.driver_body_number || null,
    todaName: row.toda_name || null,

    pickup: coord(row.pickup_lat, row.pickup_lng),
    destination: coord(row.destination_lat, row.destination_lng),
    driver: hasDriverPosition ? coord(row.driver_lat, row.driver_lng) : null,

    positionAge: timeAgo(row.position_updated_at, now),
    positionIsStale: hasDriverPosition && isStale(row.position_updated_at, now),
    hasDriverPosition,
  };
}

function coord(lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  return { lat, lng };
}

/**
 * Where to point the map when there is no driver position yet -- the pickup, so
 * the viewer at least sees the right neighbourhood instead of the middle of the
 * ocean at 0,0.
 */
export function focusPoint(vm) {
  if (!vm || vm.kind !== 'active') return null;
  return vm.driver || vm.pickup || vm.destination || null;
}

/**
 * Which screen to show before any network call.
 *
 * The distinction that matters: **no token is not an error.** Someone who types
 * `arangcada.app` into a browser -- a panelist, an LGU officer, a curious
 * driver -- has done nothing wrong, and telling them "this tracking link has
 * expired" is both false and a bad first impression of the project.
 *
 * A token that is present but unusable, or a deploy missing its config, is a
 * different case and gets the neutral expired screen.
 */
export function chooseInitialState(token, hasConfig) {
  if (!token) return 'landing';
  if (!hasConfig) return 'expired';
  return 'loading';
}
