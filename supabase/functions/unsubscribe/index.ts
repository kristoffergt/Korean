// One-click unsubscribe for the app's emails (daily recap, weekly recap,
// event reminders, Yonsei notices).
//
// Two callers, one answer:
//   * a mail client honouring the List-Unsubscribe / List-Unsubscribe-Post
//     headers: POST to this URL with the parameters in the query string and
//     "List-Unsubscribe=One-Click" as the form body (RFC 8058);
//   * kristoffergt.com/unsubscribe.html, which the footer link opens and
//     which POSTs {u, k, t} as JSON when the reader presses the button.
// A GET does nothing: link scanners and mail previews fetch links on their
// own, and an unsubscribe that happens by merely opening a URL would fire
// without anyone asking for it.
//
// The token is an HMAC of the account id and the email kind, made and
// checked inside the database (email_unsubscribe_token / unsubscribe_email),
// so the secret never leaves the vault and a link only switches off the one
// kind of email it came in. verify_jwt is off: a mail client has no session.

import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

const ALLOWED_ORIGINS = ["https://kristoffergt.com", "https://www.kristoffergt.com"];
function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const ok = ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return ok
    ? {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Vary": "Origin",
    }
    : { "Vary": "Origin" };
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST only" }, 405);

  const q = new URL(req.url).searchParams;
  let u = q.get("u") || "", k = q.get("k") || "", t = q.get("t") || "";
  if (!u || !k || !t) {
    const body = await req.json().catch(() => ({}));
    if (body && typeof body === "object") {
      u = typeof body.u === "string" ? body.u : u;
      k = typeof body.k === "string" ? body.k : k;
      t = typeof body.t === "string" ? body.t : t;
    }
  }
  if (!/^[0-9a-f-]{36}$/i.test(u) || !/^[a-z_]{1,32}$/.test(k) || !/^[0-9a-f]{64}$/i.test(t)) {
    return json({ ok: false, error: "invalid" }, 400);
  }
  const { data, error } = await admin.rpc("unsubscribe_email", { p_uid: u, p_kind: k, p_token: t.toLowerCase() });
  if (error) {
    console.error("unsubscribe_email failed", error);
    return json({ ok: false, error: "internal" }, 500);
  }
  return data === true ? json({ ok: true, kind: k }) : json({ ok: false, error: "invalid" }, 400);
});
