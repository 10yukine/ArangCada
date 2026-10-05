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

/**
 * A Storage call, tried three times. Once the account is gone nothing else
 * remembers which files were this person's, so one timeout must not leave
 * their ID photos and documents behind.
 */
async function storageCall(url: string, init: RequestInit): Promise<Response | null> {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(url, { ...init, signal: AbortSignal.timeout(10_000) }).catch(() => null);
    if (res?.ok || attempt === 3) return res;
    await new Promise((resolve) => setTimeout(resolve, attempt * 400));
  }
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
    const sessionUser = me?.ok ? await me.json() : null;
    sessionUserId = sessionUser?.id ?? null;
    const sessionPhone = credential(sessionUser?.phone ?? "");
    // A session cannot use the privileged password check to guess another
    // account's password. Bind its identifier before contacting Auth.
    if (sessionUserId && ("email" in who
      ? sessionUser.email?.toLowerCase() !== who.email
      : !sessionPhone || !("phone" in sessionPhone) || sessionPhone.phone !== who.phone)) {
      return json(401, { error: "That sign-in or password is incorrect." });
    }
  }
  if (!sessionUserId && !(await turnstilePassed(String(body.turnstile ?? ""), config.turnstileSecret))) {
    return json(403, { error: "Complete the security check and try again." });
  }

  // The service-role bearer is for CAPTCHA. Once it is switched on, Auth
  // refuses a password sign-in that carries no token, except from a request
  // with this role. A person has already been demanded above (the app's live
  // session, or Turnstile), and a Turnstile token can be redeemed only once,
  // so it could not be handed on to Auth as well.
  const signIn = await fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
    },
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
  let filesRemoved = true;
  for (const bucket of USER_FOLDER_BUCKETS) {
    const listed = await storageCall(`${config.supabaseUrl}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: service,
      body: JSON.stringify({ prefix: userId, limit: 1000, offset: 0 }),
    });
    if (!listed?.ok) filesRemoved = false;
    const items = listed?.ok ? ((await listed.json()) as { id: string | null; name: string }[]) : [];
    files[bucket] = [...(files[bucket] ?? []), ...items.filter((i) => i.id).map((i) => `${userId}/${i.name}`)];
  }
  for (const [bucket, paths] of Object.entries(files)) {
    const unique = [...new Set(paths)];
    if (!unique.length) continue;
    const removed = await storageCall(`${config.supabaseUrl}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers: service,
      body: JSON.stringify({ prefixes: unique }),
    });
    if (!removed?.ok) {
      filesRemoved = false;
      console.error(`account-deletion: could not remove ${unique.length} file(s) from ${bucket}`);
    }
  }
  const when = new Date().toLocaleString("en-PH", { timeZone: "Asia/Manila", dateStyle: "long", timeStyle: "short" });
  if (!filesRemoved && config.resendKey) {
    // Nothing retries this later, so a person has to: tell the operator which
    // folder is left. The id names no one once the account is gone.
    const alerted = await fetch("https://api.resend.com/emails", {
      method: "POST",
      signal: AbortSignal.timeout(10_000),
      headers: { Authorization: `Bearer ${config.resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "ArangCada <services@info.arangcada.app>",
        to: ["privacy@arangcada.app"],
        subject: "Finish removing a deleted account's files",
        text: `An account was deleted on ${when} (Philippine time), but its files could not all be removed ` +
          `from Storage after three tries.\n\nDelete the folder ${userId}/ from these buckets: ` +
          `${USER_FOLDER_BUCKETS.join(", ")}. The person was told this would be done within a few days.`,
      }),
    }).catch(() => null);
    if (!alerted?.ok) console.error(`account-deletion: files left in folder ${userId}/ and the operator alert failed`);
  }
  const email: string | undefined = session?.user?.email;
  if (email && config.resendKey) {
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
          (filesRemoved
            ? "Your profile, contact details, photos, discount claims, chat messages and driver documents are gone. "
            : "Your profile, contact details, discount claims and chat messages are gone. Your photos and driver " +
              "documents are still being removed; that will be finished within a few days. ") +
          "Past trips, ratings and reports are kept without your name, as our Privacy Policy " +
          "explains: https://arangcada.app/policy\n\n" +
          "If you did not do this, reply to this email or write to privacy@arangcada.app right away.",
      }),
    }).catch(() => null);
    if (!sent?.ok) console.error("account-deletion: deletion notice email failed");
  }
  return json(200, { deleted: true });
}
