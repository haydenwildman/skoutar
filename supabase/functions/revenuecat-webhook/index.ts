// Supabase Edge Function: revenuecat-webhook
//
// RevenueCat -> SKOUTAR. Marks an account's subscription paid / cancelled /
// refunded / expired. This is the ONLY path that can mark an account paid.
//
// Deploy (RevenueCat does not send a Supabase JWT, so JWT verification is off;
// the shared secret below is the authentication):
//   supabase secrets set REVENUECAT_WEBHOOK_AUTH="<long random string>"
//   supabase functions deploy revenuecat-webhook --no-verify-jwt
//
// RevenueCat dashboard -> Project settings -> Integrations -> Webhooks -> Add:
//   URL:                   https://xmzdwoqvnnwhbnntziuk.supabase.co/functions/v1/revenuecat-webhook
//   Authorization header:  the exact same string as REVENUECAT_WEBHOOK_AUTH
//
// The service-role key is injected by Supabase at runtime. It is never in the
// Flutter app, the repo, or the website.
//
// Payload: RevenueCat POSTs { "api_version": ..., "event": { id, type, app_user_id,
// product_id, ... } }. Only `event` is used. The same event id is reused on every retry.
//
// Response contract (RevenueCat treats ONLY HTTP 200 as success and otherwise retries up
// to 5 times with exponential backoff, about 2.5 / 5 / 10 / 20 / 40 minutes):
//   200  event is finished (applied, duplicate, stale, or deliberately ignored)
//   500  event is NOT finished and is stored as pending: the account's subscription row
//        does not exist yet ("retry_*" results) or the database raised an error.
//        RevenueCat's redelivery applies it later, and apply_revenuecat_event() also
//        replays pending events by itself the moment the account's row is created.
//   400  not a RevenueCat event body (RevenueCat would retry; fix the sender)
//   401  wrong / missing Authorization header      405 not POST      413 body too large

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_AUTH = Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "";
const MAX_BODY_BYTES = 200_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Constant-time string comparison.
function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  const len = Math.max(ea.length, eb.length);
  for (let i = 0; i < len; i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}

serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Fail closed: no secret configured -> nothing is accepted.
  if (WEBHOOK_AUTH.length < 16) return json({ error: "Webhook not configured" }, 500);

  const provided = req.headers.get("Authorization") ?? "";
  if (!safeEqual(provided, WEBHOOK_AUTH)) return json({ error: "Unauthorized" }, 401);

  const raw = await req.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
    return json({ error: "Payload too large" }, 413);
  }

  let event: Record<string, unknown> | undefined;
  try {
    const body = JSON.parse(raw);
    const candidate = body?.event; // RevenueCat wraps the event: { api_version, event: {...} }
    if (candidate && typeof candidate === "object" && !Array.isArray(candidate)) {
      event = candidate as Record<string, unknown>;
    }
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (!event || typeof event.id !== "string" || !event.id || typeof event.type !== "string" || !event.type) {
    return json({ error: "Malformed event" }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("apply_revenuecat_event", { p: event });
  if (error) {
    // The database function records its own failures, but a failure of the call itself
    // (network, permissions, function missing) lands here: ask RevenueCat to retry.
    console.error("apply_revenuecat_event failed", event.id, event.type, error.message);
    return json({ error: "Processing failed" }, 500);
  }

  const result = String(data);
  console.log("revenuecat event", event.id, event.type, result); // ids/labels only, no personal data

  // 'retry_*' = stored as pending, not applied yet -> non-200 so RevenueCat redelivers.
  if (result.startsWith("retry")) return json({ result }, 500);
  return json({ result });
});
