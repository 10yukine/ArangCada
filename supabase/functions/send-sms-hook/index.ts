// Supabase Send SMS Hook — delivers auth OTPs through Semaphore (Philippines).
//
// Supabase's built-in phone providers (Twilio, MessageBird, Vonage, TextLocal)
// are all US-priced. This hook replaces the built-in sender so the OTP goes out
// through Semaphore, a Philippine gateway, at a fraction of the cost per
// message to Globe/Smart/Sun/DITO numbers.
//
// ============================================================================
// THREE MODES. GET THIS RIGHT BEFORE THE PILOT.
// ============================================================================
//
//   SMS_HOOK_MODE=live             Sends via Semaphore. Logs no code.
//   SMS_HOOK_MODE=email            Emails the code to the account's own
//                                  address instead (while the Semaphore sender
//                                  name waits for telco approval). Testers can
//                                  finish registration; note that this proves
//                                  the email, not the phone number.
//   SMS_HOOK_MODE=stub             Sends nothing; logs no OTP.
//
// The mode is a Supabase secret, so switching needs no app release:
//   supabase secrets set SMS_HOOK_MODE=live
//
// Every mode first spends a permit from record_otp_send() (migration
// 20260929030000), which is where the resend schedule lives: 60 s before the
// first resend, 120 s before each later one, four codes per hour. A send the
// app did not request through that schedule is refused here.
//
// An unset or unknown mode rejects delivery. Stub mode must be explicitly
// selected for development and never records authentication codes.
//
// Flipping to live is on the pre-beta checklist.
//
// ============================================================================
// DO NOT "FIX" THIS TO USE /api/v4/otp
// ============================================================================
//
// Semaphore has an endpoint literally called OTP:
//   POST https://api.semaphore.co/api/v4/otp
//
// It is the wrong one, and it is an easy mistake to make. That endpoint
// GENERATES ITS OWN CODE and substitutes it into an `{otp}` placeholder. In
// this system Supabase generates the code and Supabase verifies it, so a
// Semaphore-generated code would never match what verifyOTP() expects --
// every user would receive a code that is guaranteed to be rejected.
//
// We send Supabase's code as ordinary message text instead.
//
// ============================================================================
// Why /priority rather than /messages
// ============================================================================
//
// /messages is the normal queue and Semaphore's own docs warn it can be
// delayed during heavy traffic. An OTP that arrives after it expires is worse
// than useless -- the user retries, spends another credit, and blames the app.
// /priority skips the queue and is not rate limited. It costs 2 credits per
// 160 characters instead of 1.
//
// At this project's volume that difference is negligible, and delivery speed is
// the entire point of a one-time code. Override with SEMAPHORE_ENDPOINT=messages
// if credits ever matter more than latency.

import { createHmac, timingSafeEqual } from 'node:crypto'
// Buffer is a global in Node but NOT in Deno's edge runtime, where it must be
// imported explicitly. Without this the hook threw
// "ReferenceError: Buffer is not defined" and returned 500 for every OTP.
//
// It stayed hidden because verifySignature() returns early when no secret is
// configured, so these three lines had never once executed -- setting
// SEND_SMS_HOOK_SECRET is what armed the path, and the failure appeared at the
// moment the endpoint was secured rather than when the code was written.
import { Buffer } from 'node:buffer'

const MODE = (Deno.env.get('SMS_HOOK_MODE') ?? 'disabled').toLowerCase()
const HOOK_SECRET = Deno.env.get('SEND_SMS_HOOK_SECRET') ?? ''
const SEMAPHORE_KEY = Deno.env.get('SEMAPHORE_API_KEY') ?? ''
const SEMAPHORE_SENDER = Deno.env.get('SEMAPHORE_SENDER_NAME') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const RESEND_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const SEMAPHORE_ENDPOINT =
  (Deno.env.get('SEMAPHORE_ENDPOINT') ?? 'priority').toLowerCase() === 'messages'
    ? 'messages'
    : 'priority'

interface HookPayload {
  // `phone` is the number already confirmed on the account. `new_phone` is the
  // one being claimed. This app registers with email+password and only then
  // attaches a number via updateUser(phone:), which is the phone-CHANGE flow,
  // so for the verification that matters here `phone` is null and the number
  // lives in `new_phone` until the code is accepted.
  user: { id: string; email?: string; phone?: string; new_phone?: string }
  sms: { otp: string }
}

const reject = (status: number, message: string) =>
  new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })

/** Spends the permit record_otp_send() issued for this user and number. */
async function consumePermit(userId: string, phone: string): Promise<boolean> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/otp_consume_permit`, {
    method: 'POST',
    signal: AbortSignal.timeout(10_000),
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_user_id: userId, p_phone: phone }),
  })
  if (!res.ok) throw new Error(`permit check failed (HTTP ${res.status})`)
  return (await res.json()) === true
}

async function sendViaEmail(to: string, otp: string): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    signal: AbortSignal.timeout(10_000),
    headers: { Authorization: `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: 'ArangCada <services@info.arangcada.app>',
      to: [to],
      subject: `${otp} is your ArangCada verification code`,
      text:
        `${otp} is your ArangCada verification code. It expires in 10 minutes.\n\n` +
        'During the beta, codes for new mobile numbers arrive by email while text ' +
        'messages are being set up. Do not share this code with anyone.',
    }),
  })
  if (!res.ok) throw new Error(`Resend HTTP ${res.status}`)
}

/** Last 4 digits only. Rule 10 forbids logging full phone numbers. */
function maskPhone(phone: string): string {
  return phone.length <= 4 ? '****' : `${'*'.repeat(phone.length - 4)}${phone.slice(-4)}`
}

/**
 * Semaphore wants a bare Philippine number, not E.164 with a plus.
 * Supabase hands us `+639171234567`; Semaphore's own examples use
 * `639998887777`.
 */
function toSemaphoreNumber(e164: string): string {
  return e164.replace(/^\+/, '')
}

/**
 * Standard Webhooks signature check.
 *
 * The secret arrives as `v1,<base64>`. Compared with timingSafeEqual rather
 * than `===` so the comparison cannot be used as a timing oracle to recover
 * the signature byte by byte.
 */
function verifySignature(body: string, headers: Headers): boolean {
  if (!HOOK_SECRET) return false

  const id = headers.get('webhook-id') ?? ''
  const timestamp = headers.get('webhook-timestamp') ?? ''
  const signatureHeader = headers.get('webhook-signature') ?? ''
  if (!id || !timestamp || !signatureHeader) return false

  // Reject stale payloads so a captured request cannot be replayed later.
  const age = Math.abs(Date.now() / 1000 - Number(timestamp))
  if (!Number.isFinite(age) || age > 300) return false

  // Supabase hands out the secret as `v1,whsec_<base64>`. BOTH prefixes have to
  // come off before decoding. `whsec_` is not base64, and Buffer.from silently
  // discards invalid characters rather than throwing, so leaving it attached
  // yields a different key and therefore a signature that can never match --
  // a 401 with nothing in the logs to explain it.
  const rawSecret = HOOK_SECRET.replace(/^v1,/, '').replace(/^whsec_/, '')
  const secretBytes = Buffer.from(rawSecret, 'base64')
  const expected = createHmac('sha256', secretBytes)
    .update(`${id}.${timestamp}.${body}`)
    .digest('base64')

  // The header may carry several space-separated versioned signatures.
  return signatureHeader.split(' ').some((part) => {
    const candidate = part.startsWith('v1,') ? part.slice(3) : part
    const a = Buffer.from(candidate)
    const b = Buffer.from(expected)
    return a.length === b.length && timingSafeEqual(a, b)
  })
}

async function sendViaSemaphore(phone: string, message: string): Promise<void> {
  // Semaphore takes form-encoded parameters, not JSON.
  const form = new URLSearchParams({
    apikey: SEMAPHORE_KEY,
    number: toSemaphoreNumber(phone),
    message,
  })
  // Omitting sendername lets Semaphore fall back to the account's default
  // registered sender name. If the account has none registered at all,
  // Semaphore throws -- which is why the pre-beta checklist has you confirm a
  // sender name exists before switching to live.
  if (SEMAPHORE_SENDER) form.set('sendername', SEMAPHORE_SENDER)

  const response = await fetch(
    `https://api.semaphore.co/api/v4/${SEMAPHORE_ENDPOINT}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form.toString(),
      signal: AbortSignal.timeout(10_000),
    },
  )

  const raw = await response.text()

  if (!response.ok) {
    // Semaphore echoes the submitted message back in its error payloads, and
    // that message contains the OTP. Log only the status and a short, scrubbed
    // hint -- never the body verbatim.
    console.error(
      `send-sms-hook: Semaphore rejected the send (HTTP ${response.status}) ` +
        `endpoint=${SEMAPHORE_ENDPOINT} senderConfigured=${SEMAPHORE_SENDER !== ''}`,
    )
    throw new Error(`Semaphore HTTP ${response.status}`)
  }

  // A 200 does not guarantee acceptance: Semaphore returns an array of message
  // objects and can report a per-message failure inside a successful response.
  try {
    const parsed = JSON.parse(raw)
    const first = Array.isArray(parsed) ? parsed[0] : parsed
    const status = String(first?.status ?? '').toLowerCase()
    if (status === 'failed' || status === 'refunded') {
      console.error(`send-sms-hook: Semaphore reported status=${status}`)
      throw new Error(`Semaphore status ${status}`)
    }
  } catch (error) {
    // A parse failure is not fatal on a 200 -- the message may well have been
    // accepted. Record it and move on rather than telling the user to retry
    // and charging them a second credit.
    if (error instanceof SyntaxError) {
      console.warn('send-sms-hook: could not parse Semaphore response body')
    } else {
      throw error
    }
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  if (MODE !== 'live' && MODE !== 'stub' && MODE !== 'email') {
    console.error('send-sms-hook: SMS_HOOK_MODE must be explicitly configured')
    return new Response(JSON.stringify({ error: { message: 'SMS provider is not configured' } }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }

  const body = await req.text()

  // Signature is mandatory whenever something is delivered. In stub mode it is
  // checked when a secret is configured and skipped when it is not, so a
  // developer can curl the endpoint locally without ceremony.
  if (MODE !== 'stub' || HOOK_SECRET) {
    if (!verifySignature(body, req.headers)) {
      console.error('send-sms-hook: signature verification failed')
      return new Response(JSON.stringify({ error: { message: 'invalid signature' } }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }
  }

  let payload: HookPayload
  try {
    payload = JSON.parse(body) as HookPayload
  } catch {
    // Logged, because a bare 400 is invisible: GoTrue reports it to the client
    // as "Invalid payload sent to hook" while the function log stays completely
    // empty, which reads like the hook was never called at all.
    console.error('send-sms-hook: body was not valid JSON')
    return new Response(JSON.stringify({ error: { message: 'invalid payload' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // new_phone first: during a phone change it is the only field carrying the
  // number the code is being sent to. Reading `phone` alone rejected every
  // registration in this app, because an account created with email+password
  // has no confirmed phone yet -- and it failed silently, since the branch
  // below used to return 400 without logging.
  const phone = payload?.user?.new_phone || payload?.user?.phone || ''
  const otp = payload?.sms?.otp ?? ''

  if (typeof phone !== 'string' || !/^\+?639\d{9}$/.test(phone) ||
      typeof otp !== 'string' || !/^\d{6}$/.test(otp)) {
    console.error(
      `send-sms-hook: payload missing ${!phone ? 'phone' : ''}` +
        `${!phone && !otp ? ' and ' : ''}${!otp ? 'otp' : ''}`,
    )
    return new Response(JSON.stringify({ error: { message: 'missing phone or otp' } }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // The resend schedule. Fail closed: if the check cannot run, send nothing.
  if (MODE !== 'stub' || SERVICE_ROLE_KEY) {
    let permitted = false
    try {
      permitted = await consumePermit(payload.user.id, phone)
    } catch (error) {
      console.error(`send-sms-hook: ${(error as Error).message}`)
      return reject(503, 'Could not send the code right now. Try again in a moment.')
    }
    if (!permitted) {
      console.warn(`send-sms-hook: no permit for ${maskPhone(phone)}; not sent`)
      return reject(429, 'Request a new code from the app and try again.')
    }
  }

  if (MODE === 'email') {
    const email = payload.user.email ?? ''
    if (!RESEND_KEY || !/^[^\s@]+@[^\s@]+$/.test(email)) {
      console.error('send-sms-hook: email mode needs RESEND_API_KEY and an account email')
      return reject(500, 'Could not send the verification code')
    }
    try {
      await sendViaEmail(email, otp)
      console.log(`send-sms-hook: code for ${maskPhone(phone)} emailed to the account`)
      return new Response(JSON.stringify({}), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    } catch (error) {
      console.error(`send-sms-hook: email send failed - ${(error as Error).message}`)
      return reject(502, 'Could not send the verification code')
    }
  }

  // Kept under 160 characters so it stays a single billable segment. It must
  // also not begin with the word "TEST" -- Semaphore silently discards those.
  const message =
    `${otp} is your ArangCada verification code. ` +
    `It expires in 10 minutes. Do not share it with anyone.`

  if (MODE !== 'live') {
    // ---- STUB MODE -------------------------------------------------------
    // Keep the delivery diagnostic without exposing an authentication code.
    console.log(
      `[send-sms-hook][STUB] no SMS sent. to=${maskPhone(phone)} OTP=[REDACTED] ` +
        `user=${payload.user?.id ?? 'unknown'}`,
    )
    return new Response(JSON.stringify({}), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  // ---- LIVE MODE ---------------------------------------------------------
  if (!SEMAPHORE_KEY) {
    // Fail loudly rather than silently falling back to stub. A live deployment
    // missing its credentials is a configuration error, not a reason to start
    // logging OTPs.
    console.error('send-sms-hook: live mode is missing SEMAPHORE_API_KEY')
    return new Response(
      JSON.stringify({ error: { message: 'SMS provider is not configured' } }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }

  try {
    await sendViaSemaphore(phone, message)
    console.log(
      `send-sms-hook: delivered to ${maskPhone(phone)} via ${SEMAPHORE_ENDPOINT}`,
    )
    return new Response(JSON.stringify({}), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error(`send-sms-hook: send failed - ${(error as Error).message}`)
    return new Response(
      JSON.stringify({ error: { message: 'could not send the verification code' } }),
      { status: 502, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
