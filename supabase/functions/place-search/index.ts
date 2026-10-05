import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
// place-search -- place suggestions for a signed-in rider, from LocationIQ.
//
// The app used to call LocationIQ itself, with the provider key compiled into
// the APK where anyone could read it. The key now stays here, in the
// LOCATIONIQ_API_KEY secret, and the app sends only the text typed.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Runs only for a signed-in caller (verify_jwt = true in config.toml), and
//     counts the search against that account with consume_place_search() on a
//     client scoped to the caller's OWN JWT -- never the service-role key.
//     That RPC is the source of truth for who may search and how often.
//   * Asks LocationIQ for at most 8 suggestions inside a fixed box around
//     Calamba. The caller cannot change the box, the country or the limit.
//   * Returns only the fields the app shows. The phone still tests every
//     result against the service area, and request_ride tests it again.
//   * Stores nothing and logs no search text.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

/// Two corners of a box around Calamba: lon,lat,lon,lat.
const VIEWBOX = "121.00,14.28,121.24,14.12";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method not allowed" });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(401, { error: "missing Authorization header" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const providerKey = Deno.env.get("LOCATIONIQ_API_KEY");
  if (!supabaseUrl || !anonKey || !providerKey) {
    console.error("place-search: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }
  const raw = (body ?? {}) as { q?: unknown };
  const q = typeof raw.q === "string" ? raw.q.trim() : "";
  if (q.length < 3 || q.length > 80) {
    return jsonResponse(400, { error: "q must be 3 to 80 characters" });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: allowed, error: budgetError } = await callerClient.rpc("consume_place_search");
  if (budgetError) {
    // 42501: the caller is not a signed-in account (the anon key alone).
    console.error("place-search: consume_place_search failed", budgetError.message);
    return jsonResponse(budgetError.code === "42501" ? 403 : 500, {
      error: "place search is unavailable",
    });
  }
  if (allowed !== true) {
    return jsonResponse(429, { error: "place search limit reached" });
  }

  const url = new URL("https://api.locationiq.com/v1/autocomplete");
  url.search = new URLSearchParams({
    key: providerKey,
    q,
    countrycodes: "ph",
    viewbox: VIEWBOX,
    bounded: "1",
    limit: "8",
    dedupe: "1",
    normalizecity: "1",
  }).toString();

  let upstream: Response;
  try {
    upstream = await fetch(url, { signal: AbortSignal.timeout(8000) });
  } catch {
    return jsonResponse(504, { error: "place search timed out" });
  }
  // LocationIQ's "nothing found".
  if (upstream.status === 404) return jsonResponse(200, []);
  if (upstream.status === 429) {
    return jsonResponse(429, { error: "place search is busy" });
  }
  if (!upstream.ok) {
    // Never echo the provider's body: it can repeat the request URL and key.
    console.error("place-search: provider answered", upstream.status);
    return jsonResponse(502, { error: "place search is unavailable" });
  }

  let places: unknown;
  try {
    places = await upstream.json();
  } catch {
    return jsonResponse(502, { error: "place search returned bad data" });
  }
  if (!Array.isArray(places) || places.some((place) =>
    place === null || typeof place !== "object" || Array.isArray(place)
  )) {
    return jsonResponse(502, { error: "place search returned bad data" });
  }
  return jsonResponse(
    200,
    places.map((place: Record<string, unknown>) => ({
      place_id: place.place_id,
      lat: place.lat,
      lon: place.lon,
      display_name: place.display_name,
      display_place: place.display_place,
      display_address: place.display_address,
    })),
  );
});
