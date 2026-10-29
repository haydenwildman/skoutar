// Supabase Edge Function: revenuecat-webhook
//
// RevenueCat -> SKOUTAR. Marks an account's subscription paid / cancelled /
// expired. This is the ONLY path that can mark an account paid.
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
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Payload too large" }, 413);

  let event: Record<string, unknown> | undefined;
  try {
    event = JSON.parse(raw)?.event;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (!event || typeof event.id !== "string" || typeof event.type !== "string") {
    return json({ error: "Malformed event" }, 400);
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await admin.rpc("apply_revenuecat_event", { p: event });
  if (error) {
    console.error("apply_revenuecat_event failed", error.message);
    return json({ error: "Processing failed" }, 500); // RevenueCat retries
  }
  const result = String(data);
  // e.g. the signup row doesn't exist yet: ask RevenueCat to retry later.
  if (result.startsWith("retry")) return json({ result }, 500);
  return json({ result });
});
