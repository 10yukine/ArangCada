import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
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

interface ResolvedNotification {
  targetUserId: string;
  targetRole: "driver" | "commuter";
  type: string;
  title: string;
  body: string;
}

serve(async (req) => {
  try {
    // This function is deployed with --no-verify-jwt because it is called by
    // a Postgres trigger via pg_net (server-to-server), which cannot attach a
    // user JWT. That makes the URL itself the only gate unless we check a
    // shared secret here -- without this, anyone who finds the function URL
    // could POST an arbitrary record and cause a real push to a real user.
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
    const oldRecord = body.old_record;
    
    if (!record || !record.status) {
      return new Response(JSON.stringify({ message: "No trip record or status" }), { status: 200 });
    }

    let resolved: ResolvedNotification | null = null;

    switch (record.status) {
      case "driver_assigned":
        if (record.driver_id) {
          resolved = {
            targetUserId: record.driver_id,
            targetRole: "driver",
            type: "ride_offer",
            title: "New Ride Offer",
            body: `Pickup: ${record.pickup_label || 'Special ride requested nearby'}`,
          };
        }
        break;

      case "accepted":
      case "driver_en_route":
        if (record.rider_id) {
          resolved = {
            targetUserId: record.rider_id,
            targetRole: "commuter",
            type: "ride_updated",
            title: "Driver on the way",
            body: `${record.driver_display_name || 'A driver'} accepted your ride and is heading your way.`,
          };
        }
        break;

      case "arrived":
        if (record.rider_id) {
          resolved = {
            targetUserId: record.rider_id,
            targetRole: "commuter",
            type: "ride_updated",
            title: "Driver arrived",
            body: `${record.driver_display_name || 'Your driver'} has arrived at your pickup location.`,
          };
        }
        break;

      case "completed":
        if (record.rider_id) {
          resolved = {
            targetUserId: record.rider_id,
            targetRole: "commuter",
            type: "ride_updated",
            title: "Trip completed",
            body: "You arrived at your destination. Tap to view your receipt.",
          };
        }
        break;

      case "cancelled_by_driver":
        if (record.rider_id) {
          resolved = {
            targetUserId: record.rider_id,
            targetRole: "commuter",
            type: "ride_cancelled",
            title: "Ride cancelled",
            body: `${record.driver_display_name || 'Your driver'} cancelled the ride. Tap to rebook.`,
          };
        }
        break;

      case "cancelled_by_rider": {
        const assignedDriverId = record.driver_id || oldRecord?.driver_id;
        if (assignedDriverId) {
          resolved = {
            targetUserId: assignedDriverId,
            targetRole: "driver",
            type: "ride_cancelled",
            title: "Ride cancelled",
            body: "The passenger has cancelled this ride request.",
          };
        }
        break;
      }

      case "no_driver_available":
        if (record.rider_id) {
          resolved = {
            targetUserId: record.rider_id,
            targetRole: "commuter",
            type: "ride_expired",
            title: "No driver found",
            body: "No drivers available nearby right now. Tap to try again.",
          };
        }
        break;

      default:
        break;
    }

    if (!resolved) {
      return new Response(JSON.stringify({ message: `No push notification required for status ${record.status}` }), { status: 200 });
    }

    // Connect to Supabase to fetch FCM tokens for the recipient user
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: tokens, error } = await supabase
      .from('push_tokens')
      .select('fcm_token, platform')
      .eq('user_id', resolved.targetUserId)
      .order('updated_at', { ascending: false })
      .limit(32);

    if (error || !tokens || tokens.length === 0) {
      console.log("No FCM tokens found for user", resolved.targetUserId);
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
            title: resolved.title,
            body: resolved.body,
          },
          data: {
            type: resolved.type,
            trip_id: record.id,
            target_role: resolved.targetRole,
          },
        }
      };

      const response = await fetch(fcmEndpoint, {
        signal: AbortSignal.timeout(10_000),
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

    return new Response(JSON.stringify({ message: `Sent ${successCount} pushes to ${resolved.targetRole}` }), { status: 200 });

  } catch (error: any) {
    console.error("Webhook processing failed", error);
    return new Response(JSON.stringify({ error: 'Could not process notification' }), { status: 500 });
  }
});
