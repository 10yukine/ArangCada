// Self-service account deletion. See delete.ts for the flow and config.toml
// for why verify_jwt is false.
import { handle } from "./delete.ts";

Deno.serve((req) =>
  handle(req, {
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    turnstileSecret: Deno.env.get("TURNSTILE_SECRET_KEY") ?? "",
    resendKey: Deno.env.get("RESEND_API_KEY") ?? "",
  })
);
