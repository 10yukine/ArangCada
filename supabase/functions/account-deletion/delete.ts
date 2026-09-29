// Deletes the caller's account (Google Play account-deletion requirement).
//
// Called by the app (Profile > Settings > Delete account) and by
// arangcada.app/delete-account for people who no longer have the app. Both
// send the account's email or mobile number and its password; signing in here
// proves ownership at the moment of deletion, so an unlocked phone or a stolen
// session is not enough, and the public page needs no Supabase key.
//
// Guessing passwords through this endpoint is blocked two ways: a request
// from the app must also carry that same account's live session, and any
// other request (the website) must pass a Cloudflare Turnstile check before a
// sign-in is even attempted. After deleting, a notice goes to the account's
// email so a deletion the owner did not make is noticed.
//
// delete_account() (20260929010000) removes the account and de-identifies the
// records we must keep, then returns the Storage files to remove. Storage
// cannot be cleaned from SQL, so that happens here, after the account is gone.
//
// Kept free of Deno-only APIs so Node can test it (delete_test.ts).

export type Config = {
  supabaseUrl: string; anonKey: string; serviceRoleKey: string;
  turnstileSecret: string; resendKey: string;
};

// Buckets whose objects live under "<user id>/"; listing them also catches
// uploads never recorded in a row (e.g. a claim photo whose claim was abandoned).
const USER_FOLDER_BUCKETS = ["profile-photos", "discount-eligibility-ids", "driver-documents"];
const cors = {
  "Access-Control-Allow-Origin": "https://arangcada.app",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

async function turnstilePassed(token: string, secret: string): Promise<boolean> {
  if (!token || !secret) return false;
  const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret, response: token }),
  }).catch(() => null);
  return Boolean(res?.ok && (await res.json())?.success === true);
}

/** Email as typed; a PH mobile number (09.., 9.., 63.., +63..) as +639XXXXXXXXX. */
export function credential(identifier: string): { email: string } | { phone: string } | null {
  const value = identifier.trim();
  if (value.includes("@")) return /^[^\s@]+@[^\s@]+$/.test(value) ? { email: value.toLowerCase() } : null;
  const digits = value.replace(/[\s()-]/g, "").replace(/^\+/, "");
  const national = digits.replace(/^63/, "").replace(/^0/, "");
  return /^9\d{9}$/.test(national) ? { phone: `+63${national}` } : null;
}

export async function handle(req: Request, config: Config): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  if (!config.supabaseUrl || !config.anonKey || !config.serviceRoleKey) {
    console.error("account-deletion: Supabase configuration is not set");
    return json(500, { error: "Account deletion is unavailable right now. Try again later." });
  }

  let body: { identifier?: unknown; password?: unknown; turnstile?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid request" });
  }
  const who = typeof body.identifier === "string" ? credential(body.identifier) : null;
  if (!who || typeof body.password !== "string" || !body.password) {
    return json(400, { error: "Enter your email or mobile number and your password." });
  }

  // The app sends its session; only that account may be deleted through it.
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  let sessionUserId: string | null = null;
  if (bearer && bearer !== config.anonKey) {
    const me = await fetch(`${config.supabaseUrl}/auth/v1/user`, {
      signal: AbortSignal.timeout(10_000),
      headers: { apikey: config.anonKey, Authorization: `Bearer ${bearer}` },
    }).catch(() => null);
    sessionUserId = me?.ok ? ((await me.json())?.id ?? null) : null;
  }
  if (!sessionUserId && !(await turnstilePassed(String(body.turnstile ?? ""), config.turnstileSecret))) {
    return json(403, { error: "Complete the security check and try again." });
  }

  const signIn = await fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: { apikey: config.anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ ...who, password: body.password }),
  });
  if (signIn.status === 429) return json(429, { error: "Too many attempts. Wait a few minutes and try again." });
  const session = signIn.ok ? await signIn.json() : null;
  const userId: string | undefined = session?.user?.id;
  if (!userId || (sessionUserId && sessionUserId !== userId)) {
    return json(401, { error: "That sign-in or password is incorrect." });
  }

  const service = {
    apikey: config.serviceRoleKey,
    Authorization: `Bearer ${config.serviceRoleKey}`,
    "Content-Type": "application/json",
  };
  const deleted = await fetch(`${config.supabaseUrl}/rest/v1/rpc/delete_account`, {
    method: "POST",
    signal: AbortSignal.timeout(20_000),
    headers: service,
    body: JSON.stringify({ p_user_id: userId }),
  });
  if (!deleted.ok) {
    const error = await deleted.json().catch(() => ({}));
    // 55000 = a reason the person can act on (live ride, admin, demo account).
    if (error?.code === "55000") return json(409, { error: error.message });
    console.error(`account-deletion: delete_account failed (HTTP ${deleted.status})`, error?.code);
    return json(500, { error: "Your account could not be deleted. Try again later." });
  }
  const files = (await deleted.json()) as Record<string, string[]>;

  // The account is gone; from here failures are logged, never returned.
  for (const bucket of USER_FOLDER_BUCKETS) {
    const listed = await fetch(`${config.supabaseUrl}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      signal: AbortSignal.timeout(10_000),
      headers: service,
      body: JSON.stringify({ prefix: userId, limit: 1000, offset: 0 }),
    }).catch(() => null);
    const items = listed?.ok ? ((await listed.json()) as { id: string | null; name: string }[]) : [];
    files[bucket] = [...(files[bucket] ?? []), ...items.filter((i) => i.id).map((i) => `${userId}/${i.name}`)];
  }
  for (const [bucket, paths] of Object.entries(files)) {
    const unique = [...new Set(paths)];
    if (!unique.length) continue;
    const removed = await fetch(`${config.supabaseUrl}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      signal: AbortSignal.timeout(10_000),
      headers: service,
      body: JSON.stringify({ prefixes: unique }),
    }).catch(() => null);
    if (!removed?.ok) console.error(`account-deletion: could not remove ${unique.length} file(s) from ${bucket}`);
  }
  const email: string | undefined = session?.user?.email;
  if (email && config.resendKey) {
    const when = new Date().toLocaleString("en-PH", { timeZone: "Asia/Manila", dateStyle: "long", timeStyle: "short" });
    const sent = await fetch("https://api.resend.com/emails", {
      method: "POST",
      signal: AbortSignal.timeout(10_000),
      headers: { Authorization: `Bearer ${config.resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "ArangCada <services@info.arangcada.app>",
        to: [email],
        reply_to: "privacy@arangcada.app",
        subject: "Your ArangCada account was deleted",
        text: `Your ArangCada account (${email}) was deleted on ${when} (Philippine time).\n\n` +
          "Your profile, contact details, photos, discount claims, chat messages and driver documents " +
          "are gone. Past trips, ratings and reports are kept without your name, as our Privacy Policy " +
          "explains: https://arangcada.app/policy\n\n" +
          "If you did not do this, reply to this email or write to privacy@arangcada.app right away.",
      }),
    }).catch(() => null);
    if (!sent?.ok) console.error("account-deletion: deletion notice email failed");
  }
  return json(200, { deleted: true });
}
