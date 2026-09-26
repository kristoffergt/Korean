// Sends a notification to the owner's phones as a Web Push. Three callers:
//
//   * the `notifications_push` trigger (push_notifications_migration.sql),
//     POSTing {notification_id} with the shared secret in x-push-secret;
//   * the app, asking for the VAPID public key it subscribes with
//     ({action: "public-key"}, needs nothing: the key is public by design);
//   * the app, right after push is switched on, asking for one test push to
//     the device it just registered ({action: "test", endpoint}, needs the
//     caller's own session).
//
// verify_jwt is off because the trigger has no user session to send; every
// path that does anything checks its own credential below.
//
// The payload carries the row's type and params rather than finished text:
// the phone's service worker renders it in the phone's own language with the
// strings the app last handed it, the same way the bell does.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { generateVapidKeys, sendPush, type VapidKeys } from "./webpush.ts";

const SUBJECT = "https://kristoffergt.com";
// A push record has to fit in 4 KB once encrypted. Korean is three bytes a
// character, so the body is cut by BYTES, not characters.
const MAX_BODY_BYTES = 1800;

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

// The page asks for the public key and a test push from the browser, so
// those two need CORS -- but only for this site, not for any page on the web.
// The trigger's own call comes from pg_net and carries no Origin at all.
const ALLOWED_ORIGINS = ["https://kristoffergt.com", "https://www.kristoffergt.com"];
function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const ok = ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return ok
    ? {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    }
    : { "Vary": "Origin" };
}

// Constant-time, so the shared secret cannot be guessed a byte at a time
// from how long a wrong one takes to be refused.
function sameSecret(a: string | null, b: string | null): boolean {
  if (!a || !b) return false;
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

let configCache: { keys: VapidKeys; secret: string } | null = null;

// The key pair is made here the first time anything asks for it. The update
// only applies while vapid_public is still empty, so two cold starts racing
// each other both end up reading back the one pair that won.
async function loadConfig(): Promise<{ keys: VapidKeys; secret: string }> {
  if (configCache) return configCache;
  let { data, error } = await admin.from("push_config").select("*").eq("id", 1).maybeSingle();
  if (error || !data) throw new Error("push_config unavailable: " + (error?.message ?? "no row"));
  if (!data.vapid_public) {
    const k = await generateVapidKeys();
    await admin.from("push_config")
      .update({ vapid_public: k.publicKey, vapid_private_jwk: k.privateJwk })
      .eq("id", 1).is("vapid_public", null);
    ({ data, error } = await admin.from("push_config").select("*").eq("id", 1).maybeSingle());
    if (error || !data?.vapid_public) throw new Error("could not store VAPID keys");
  }
  configCache = { keys: { publicKey: data.vapid_public, privateJwk: data.vapid_private_jwk }, secret: data.webhook_secret };
  return configCache;
}

function cutToBytes(s: string | null, max: number): string | null {
  if (!s) return s;
  const enc = new TextEncoder();
  if (enc.encode(s).length <= max) return s;
  let out = s;
  while (out.length && enc.encode(out + "…").length > max) out = out.slice(0, -1);
  return out + "…";
}

interface SubRow { id: number; endpoint: string; p256dh: string; auth: string; }

// 404 and 410 mean the device has gone (app deleted, permission revoked,
// subscription rotated), so its row goes too.
async function deliver(subs: SubRow[], payload: unknown, keys: VapidKeys) {
  const results = await Promise.all(subs.map(async (s) => {
    try {
      const res = await sendPush(s, payload, keys, SUBJECT);
      if (res.status === 404 || res.status === 410) {
        await admin.from("push_subscriptions").delete().eq("id", s.id);
        return { id: s.id, status: res.status, gone: true };
      }
      if (res.ok) {
        await admin.from("push_subscriptions").update({ last_success_at: new Date().toISOString() }).eq("id", s.id);
      }
      return { id: s.id, status: res.status, detail: res.ok ? undefined : (await res.text()).slice(0, 300) };
    } catch (e) {
      return { id: s.id, status: 0, detail: String(e).slice(0, 300) };
    }
  }));
  return results;
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (body: unknown, status = 200): Response =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* empty body is handled below */ }

  let config;
  try { config = await loadConfig(); } catch (e) {
    // The detail goes to the function's log, not to whoever called.
    console.error("send-push config", e);
    return json({ error: "unavailable" }, 500);
  }

  if (body.action === "public-key") {
    return json({ publicKey: config.keys.publicKey });
  }

  if (body.action === "test") {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: userData } = await admin.auth.getUser(token);
    const user = userData?.user;
    if (!user) return json({ error: "not signed in" }, 401);
    const endpoint = typeof body.endpoint === "string" ? body.endpoint : "";
    const { data: subs } = await admin.from("push_subscriptions")
      .select("id, endpoint, p256dh, auth").eq("user_id", user.id).eq("endpoint", endpoint);
    if (!subs || subs.length === 0) return json({ error: "device not registered" }, 404);
    const results = await deliver(subs as SubRow[], { type: "push_test" }, config.keys);
    return json({ results });
  }

  // From here on it is the trigger, and only the trigger knows the secret.
  if (!sameSecret(req.headers.get("x-push-secret"), config.secret)) return json({ error: "forbidden" }, 403);
  const id = Number(body.notification_id);
  if (!Number.isFinite(id)) return json({ error: "notification_id required" }, 400);

  const { data: n } = await admin.from("notifications")
    .select("id, user_id, type, title, body, params").eq("id", id).maybeSingle();
  if (!n) return json({ skipped: "no such notification" });

  const { data: pref } = await admin.from("notification_prefs")
    .select("push").eq("user_id", n.user_id).eq("type", n.type).maybeSingle();
  if (pref && pref.push === false) return json({ skipped: "push off for this type" });

  const { data: subs } = await admin.from("push_subscriptions")
    .select("id, endpoint, p256dh, auth").eq("user_id", n.user_id);
  if (!subs || subs.length === 0) return json({ skipped: "no devices" });

  const payload = {
    id: n.id, type: n.type, params: n.params ?? null,
    title: n.title, body: cutToBytes(n.body, MAX_BODY_BYTES),
  };
  const results = await deliver(subs as SubRow[], payload, config.keys);
  return json({ results });
});
