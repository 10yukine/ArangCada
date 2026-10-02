// Public ride-tracking page — network and DOM.
//
// All decision logic lives in render.js so it can be tested without a browser.
// This file fetches, polls, and pushes values into elements.
//
// It runs for someone with no ArangCada account, quite possibly on a poor
// connection, so it fails soft everywhere: a failed poll keeps the last good
// render rather than blanking the screen.

import {
  parseToken,
  toViewModel,
  focusPoint,
  chooseInitialState,
} from './render.js';

const POLL_MS = 10_000;
const POLL_MS_BACKOFF = 30_000;
const FAILURES_BEFORE_BACKOFF = 2;

const cfg = window.ARANGCADA_CONFIG || {};
const MAPLIBRE = 'https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl';
// The browser refuses either file if the CDN ever serves different bytes.
// Recompute both when the version changes:
//   curl -s <url> | openssl dgst -sha384 -binary | openssl base64 -A
const MAPLIBRE_INTEGRITY = {
  css: 'sha384-MinO0mNliZ3vwppuPOUnGa+iq619pfMhLVUXfC4LHwSCvF9H+6P/KO4Q7qBOYV5V',
  js: 'sha384-SYKAG6cglRMN0RVvhNeBY0r3FYKNOJtznwA0v7B5Vp9tr31xAHsZC0DqkQ/pZDmj',
};
// MapLibre's own attribution control writes the map style's attribution HTML
// into the page through a sanitizer that every release before 6.4.1 gets wrong
// (GHSA-jrc7-96c5-q579). 6.x is ESM-only and needs a newer browser than many
// phones that open a shared link have, so the control is switched off and the
// credits are fixed text instead. Update them if MAPTILER_STYLE_URL ever
// points at another provider.
const MAP_CREDITS = [
  ['\u00a9 MapTiler', 'https://www.maptiler.com/copyright/'],
  ['\u00a9 OpenStreetMap contributors', 'https://www.openstreetmap.org/copyright'],
];

const el = (id) => document.getElementById(id);
const show = (id) => el(id).classList.remove('hidden');
const hide = (id) => el(id).classList.add('hidden');

let map = null;
let driverMarker = null;
let pollTimer = null;
let consecutiveFailures = 0;
let stopped = false;
let hasRenderedOnce = false;
let inFlight = false;
let mapLibrary = null;
let lastRows = null;

const token = parseToken(window.location.pathname, window.location.search);

/**
 * Calls the one function anon is allowed to execute. Everything else in the
 * schema denies anon outright, so there is no other endpoint to get wrong.
 */
async function fetchTrip() {
  const response = await fetch(`${cfg.supabaseUrl}/rest/v1/rpc/ride_share_view`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: cfg.supabaseAnonKey,
      Authorization: `Bearer ${cfg.supabaseAnonKey}`,
    },
    body: JSON.stringify({ p_token: token }),
    signal: AbortSignal.timeout(15_000),
  });

  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

function renderExpired() {
  stopPolling();
  hide('state-loading');
  hide('state-active');
  hide('state-landing');
  show('state-expired');
}

/**
 * Someone typed the bare domain. Not an error -- tell them what this is.
 */
function renderLanding() {
  stopPolling();
  hide('state-loading');
  hide('state-active');
  hide('state-expired');
  show('state-landing');
}

function renderActive(vm) {
  hide('state-loading');
  hide('state-expired');
  hide('state-landing');
  show('state-active');

  // The status row is a live region: re-setting the same text on every poll
  // would make screen readers repeat it every ten seconds.
  const status = el('status-text');
  if (status.textContent !== vm.statusText) status.textContent = vm.statusText;
  el('status-dot').className = `dot ${vm.statusTone === 'alert' ? 'dot-alert' : 'dot-live'}`;

  el('driver-name').textContent = vm.driverName;

  setRow('body-row', 'body-number', vm.bodyNumber);
  setRow('toda-row', 'toda-name', vm.todaName);

  renderAge(vm);

  loadMapLibrary()
    .then(() => updateMap(vm))
    // A blocked map CDN must not discard usable trip details.
    .catch(() => console.error('track_web: map unavailable'));
  hasRenderedOnce = true;
}

function renderAge(vm) {
  const age = el('position-age');
  if (!vm.hasDriverPosition) {
    age.textContent = 'Waiting for the driver’s location…';
    age.classList.remove('warn');
  } else {
    age.textContent = `Location updated ${vm.positionAge}`;
    // A stale dot presented as current is misleading -- it reads as "the
    // tricycle stopped" when it usually means the phone lost signal.
    age.classList.toggle('warn', vm.positionIsStale);
  }
}

function setRow(rowId, valueId, value) {
  const row = el(rowId);
  if (value) {
    el(valueId).textContent = value;
    row.hidden = false;
  } else {
    row.hidden = true;
  }
}

// MapLibre is ~850 KB. Only a live trip draws a map, so the landing and
// expired pages never download it.
function loadMapLibrary() {
  if (!mapLibrary) {
    const css = Object.assign(document.createElement('link'), {
      rel: 'stylesheet', href: `${MAPLIBRE}.css`, integrity: MAPLIBRE_INTEGRITY.css, crossOrigin: 'anonymous',
    });
    const script = Object.assign(document.createElement('script'), {
      src: `${MAPLIBRE}.js`, integrity: MAPLIBRE_INTEGRITY.js, crossOrigin: 'anonymous',
    });
    mapLibrary = Promise.all([css, script].map((node) => new Promise((resolve, reject) => {
      node.onload = resolve;
      node.onerror = reject;
    })));
    document.head.append(css, script);
  }
  return mapLibrary;
}

function updateMap(vm) {
  const focus = focusPoint(vm);
  if (!focus) return;

  if (!map) {
    map = new maplibregl.Map({
      container: 'map',
      style: cfg.mapStyleUrl,
      center: [focus.lng, focus.lat],
      zoom: 15,
      attributionControl: false,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    addCredits();
  }

  if (vm.driver) {
    if (!driverMarker) {
      driverMarker = addMarker(vm.driver, 'marker-driver', 'Tricycle location');
    } else {
      driverMarker.setLngLat([vm.driver.lng, vm.driver.lat]);
    }
    map.easeTo({ center: [vm.driver.lng, vm.driver.lat], duration: 800 });
  }
}

function addCredits() {
  const inner = Object.assign(document.createElement('div'), { className: 'maplibregl-ctrl-attrib-inner' });
  for (const [text, href] of MAP_CREDITS) {
    inner.append(Object.assign(document.createElement('a'), {
      textContent: text, href, target: '_blank', rel: 'noopener noreferrer',
    }), ' ');
  }
  const box = Object.assign(document.createElement('div'), { className: 'maplibregl-ctrl maplibregl-ctrl-attrib' });
  box.append(inner);
  map.getContainer().querySelector('.maplibregl-ctrl-bottom-right').append(box);
}

function addMarker(point, className, label) {
  const node = document.createElement('div');
  node.className = className;
  node.setAttribute('role', 'img');
  const marker = new maplibregl.Marker({ element: node }).setLngLat([point.lng, point.lat]).addTo(map);
  // addTo() replaces any label with MapLibre's generic "Map marker".
  node.setAttribute('aria-label', label);
  return marker;
}

async function tick() {
  if (stopped || inFlight) return;
  inFlight = true;

  try {
    const rows = await fetchTrip();
    consecutiveFailures = 0;
    hide('reconnecting');

    const vm = toViewModel(rows);
    if (vm.kind === 'expired') {
      renderExpired();
      return;
    }
    lastRows = rows;
    renderActive(vm);
  } catch (error) {
    consecutiveFailures += 1;
    // Keep whatever is already on screen. Blanking a map because one poll
    // failed is worse than showing a slightly old position with a note.
    if (hasRenderedOnce) {
      show('reconnecting');
      // The position on screen keeps getting older while this page cannot
      // reach the server. Without this it went on reading "updated just now".
      renderAge(toViewModel(lastRows));
    } else if (consecutiveFailures >= FAILURES_BEFORE_BACKOFF) {
      // Network failure does not establish that a link has expired.
      el('state-loading').querySelector('p').textContent =
        'Unable to connect. Retrying…';
    }
  } finally {
    inFlight = false;
  }

  schedule();
}

function schedule() {
  clearTimeout(pollTimer);
  if (stopped || document.hidden) return;
  const delay = consecutiveFailures >= FAILURES_BEFORE_BACKOFF ? POLL_MS_BACKOFF : POLL_MS;
  pollTimer = setTimeout(tick, delay);
}

function stopPolling() {
  stopped = true;
  clearTimeout(pollTimer);
}

// A phone left in a pocket must not poll all afternoon. Pause when the tab is
// hidden, and refresh immediately when the viewer comes back rather than
// showing them a stale screen for up to ten seconds.
document.addEventListener('visibilitychange', () => {
  if (stopped) return;
  if (document.hidden) {
    clearTimeout(pollTimer);
  } else {
    tick();
  }
});

function start() {
  const hasConfig = Boolean(cfg.supabaseUrl && cfg.supabaseAnonKey);

  if (!hasConfig) {
    // A deploy without config.js. Loud in the console for whoever deployed it,
    // neutral on screen for the visitor.
    console.error('track_web: config.js missing. Run build-config.js with SUPABASE_URL, SUPABASE_ANON_KEY and MAPTILER_STYLE_URL set.');
  }

  switch (chooseInitialState(token, hasConfig)) {
    case 'landing':
      renderLanding();
      return;
    case 'expired':
      renderExpired();
      return;
    default:
      tick();
  }
}

start();
