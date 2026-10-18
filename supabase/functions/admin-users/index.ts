// Supabase Edge Function: admin-users
//
// NOTHING IN THE CURRENT APP CALLS THIS FUNCTION (the in-app admin panel was
// removed). If you do not use it, DELETE it from Supabase to remove the attack
// surface:   supabase functions delete admin-users
//
// If you keep it: it needs the service-role key, which is injected by Supabase
// and must never be shipped in the app. The function re-checks that the CALLER
// is an admin (profiles.tier = 'admin', a column users cannot change themselves)
// before doing anything privileged.
//
// Optional secret:  ALLOWED_ORIGINS="https://your-app.example,https://www.your-app.example"
// (comma separated). Browser calls from other origins are not given CORS access.
// Admin accounts should have MFA enabled in the Supabase dashboard.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ALLOWED = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}$/;
const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
const MAX_BODY_BYTES = 10_000;
const MIN_PASSWORD = 12;
const CREATABLE_TIERS = ["basic", "plus"]; // admins are never created through this API

function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const h: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Vary": "Origin",
  };
  if (origin && ALLOWED.includes(origin)) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

function json(req: Request, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsFor(req), "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(req) });
  if (req.method !== "POST") return json(req, 405, { error: "Method not allowed" });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json(req, 401, { error: "Unauthorized" });

  // Client scoped to the CALLER's own JWT, used only to verify who is calling.
  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await callerClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json(req, 401, { error: "Unauthorized" });

  const { data: profile } = await callerClient.from("profiles").select("tier").eq("id", user.id).single();
  if (profile?.tier !== "admin") return json(req, 403, { error: "Forbidden" });

  const len = Number(req.headers.get("content-length") ?? "0");
  if (len > MAX_BODY_BYTES) return json(req, 413, { error: "Request too large" });

  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return json(req, 413, { error: "Request too large" });
    body = JSON.parse(raw);
  } catch {
    return json(req, 400, { error: "Invalid JSON" });
  }
  const action = body.action;

  // Service role: full privileges. Server-side only, never returned to the caller.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  try {
    if (action === "listUsers") {
      const page = Math.max(1, Math.min(1000, Number(body.page ?? 1) || 1));
      const { data: authList, error: authErr } = await admin.auth.admin.listUsers({ page, perPage: 200 });
      if (authErr) throw authErr;
      const ids = authList.users.map((u) => u.id);
      const { data: profiles, error: profErr } = await admin.from("profiles").select().in("id", ids);
      if (profErr) throw profErr;
      const byId = new Map((profiles ?? []).map((p: Record<string, unknown>) => [p.id as string, p]));
      const users = authList.users.map((u) => ({ ...(byId.get(u.id) ?? { id: u.id }), email: u.email ?? "" }));
      return json(req, 200, { users, page });
    }

    if (action === "createUser") {
      const { username, email, password, tier } = body as Record<string, string>;
      if (typeof email !== "string" || !EMAIL_RE.test(email)) return json(req, 400, { error: "Invalid email" });
      if (typeof password !== "string" || password.length < MIN_PASSWORD || password.length > 128) {
        return json(req, 400, { error: `Password must be ${MIN_PASSWORD}-128 characters` });
      }
      if (typeof username !== "string" || !USERNAME_RE.test(username)) return json(req, 400, { error: "Invalid username" });
      if (tier !== undefined && !CREATABLE_TIERS.includes(tier)) return json(req, 400, { error: "Invalid tier" });
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { username },
      });
      if (error) throw error;
      if (tier && tier !== "basic") {
        await admin.from("profiles").update({ tier }).eq("id", data.user!.id);
      }
      return json(req, 200, { ok: true, userId: data.user!.id });
    }

    if (action === "resetPassword") {
      const { userId, newPassword } = body as Record<string, string>;
      if (typeof userId !== "string" || !UUID_RE.test(userId)) return json(req, 400, { error: "Invalid user id" });
      if (typeof newPassword !== "string" || newPassword.length < MIN_PASSWORD || newPassword.length > 128) {
        return json(req, 400, { error: `Password must be ${MIN_PASSWORD}-128 characters` });
      }
      const { error } = await admin.auth.admin.updateUserById(userId, { password: newPassword });
      if (error) throw error;
      return json(req, 200, { ok: true });
    }

    if (action === "deleteUser") {
      const { userId } = body as Record<string, string>;
      if (typeof userId !== "string" || !UUID_RE.test(userId)) return json(req, 400, { error: "Invalid user id" });
      if (userId === user.id) return json(req, 400, { error: "You cannot delete your own admin account here" });
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw error;
      return json(req, 200, { ok: true });
    }

    return json(req, 400, { error: "Unknown action" });
  } catch (err) {
    console.error("admin-users error:", err); // details stay in the function logs
    return json(req, 400, { error: "Request failed" });
  }
});
