// Resend email.received webhook -> forwards support@/legal@/privacy@ mail.
// See forward.ts for the flow and config.toml for why verify_jwt is false.
import { handle } from "./forward.ts";

Deno.serve((req) =>
  handle(req, {
    apiKey: Deno.env.get("RESEND_API_KEY") ?? "",
    webhookSecret: Deno.env.get("RESEND_INBOUND_WEBHOOK_SECRET") ?? "",
    forwardTo: Deno.env.get("INBOUND_FORWARD_TO") ?? "",
    supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
    serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  })
);
