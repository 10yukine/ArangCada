import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWT } from "https://esm.sh/google-auth-library@9.0.0";

const serviceAccountKey = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY');
if (!serviceAccountKey) {
  console.error("Missing FIREBASE_SERVICE_ACCOUNT_KEY");
}

let serviceAccount: any = null;
if (serviceAccountKey) {
  try {
    serviceAccount = JSON.parse(serviceAccountKey);
  } catch (error) {
    console.error("Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY", error);
  }
}

const getAccessToken = async () => {
  if (!serviceAccount) return null;
  const client = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const tokens = await client.authorize();
  return tokens.access_token;
};

const webhookSecret = Deno.env.get('WEBHOOK_SECRET');

serve(async (req) => {
  try {
    // This function is deployed with --no-verify-jwt because it is called by
    // a Postgres trigger via pg_net (server-to-server), which cannot attach a
    // user JWT. That makes the URL itself the only gate unless we check a
    // shared secret here -- without this, anyone who finds the function URL
    // could POST an arbitrary record and cause a real push to a real driver.
    if (webhookSecret) {
      const provided = req.headers.get('x-webhook-secret');
      if (provided !== webhookSecret) {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
      }
    } else {
      console.error('WEBHOOK_SECRET is not set; refusing unauthenticated webhook calls');
      return new Response(JSON.stringify({ error: 'Server misconfigured' }), { status: 500 });
    }

    const body = await req.json();
    const record = body.record;
    
    // Only dispatch when a driver is assigned
    if (!record || record.status !== 'driver_assigned') {
      return new Response(JSON.stringify({ message: "Not driver_assigned" }), { status: 200 });
    }

    const driverId = record.driver_id;
    if (!driverId) {
      return new Response(JSON.stringify({ message: "No driver_id" }), { status: 200 });
    }

    // Connect to Supabase to fetch FCM tokens for the driver
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: tokens, error } = await supabase
      .from('push_tokens')
      .select('fcm_token, platform')
      .eq('user_id', driverId);

    if (error || !tokens || tokens.length === 0) {
      console.log("No FCM tokens found for driver", driverId);
      return new Response(JSON.stringify({ message: "No tokens found" }), { status: 200 });
    }

    const accessToken = await getAccessToken();
    if (!accessToken) {
      return new Response(JSON.stringify({ error: "Missing Firebase credentials" }), { status: 500 });
    }

    const projectId = serviceAccount.project_id;
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    let successCount = 0;
    
    for (const tokenRow of tokens) {
      const fcmToken = tokenRow.fcm_token;
      const message = {
        message: {
          token: fcmToken,
          notification: {
            title: "New Ride Offer",
            body: `Pickup: ${record.pickup_label || 'Unknown'}`,
          },
          data: {
            type: "ride_offer",
            trip_id: record.id,
          },
        }
      };

      const response = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      });

      if (response.ok) {
        successCount++;
      } else {
        const err = await response.text();
        console.error("FCM Send Error:", err);
      }
    }

    return new Response(JSON.stringify({ message: `Sent ${successCount} pushes` }), { status: 200 });

  } catch (error: any) {
    console.error("Webhook processing failed", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});
