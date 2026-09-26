// Sign in with a display name instead of an email, without ever telling the
// caller whose email that name belongs to.
//
// The page used to call email_for_display_name() straight from the sign-in
// screen, which handed the account's email to anyone who typed a name (the
// names are on the leaderboards). Now the name, the password and the lookup
// all stay here: the email is used for one password grant against Auth and
// never leaves this function. Only a caller who also has the right password
// gets anything back, and what they get is their own session.
//
// verify_jwt is off because this IS the sign-in; nobody has a session yet.
// An unknown name still makes the password grant (against an address that
// cannot exist), so a wrong name and a wrong password take the same time and
// get the same answer.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
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
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* handled below */ }
  const name = typeof body.name === "string" ? body.name.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!name || !password || name.length > 64 || password.length > 256) {
    return json({ error: "invalid_credentials", message: "Invalid login credentials" }, 400);
  }

  let email: string | null = null;
  try {
    const { data } = await admin.rpc("email_for_display_name", { dname: name });
    if (typeof data === "string" && data) email = data;
  } catch { /* treated as not found */ }

  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { "apikey": ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: email ?? `no-such-user-${crypto.randomUUID()}@invalid.invalid`, password }),
  });
  const out = await res.json().catch(() => ({}));
  if (!email || !res.ok || !out.access_token) {
    // "Email not confirmed" is only worth passing on for a name that exists;
    // every other failure reads the same as a wrong password.
    const code = email && out && out.error_code === "email_not_confirmed" ? "email_not_confirmed" : "invalid_credentials";
    const message = code === "email_not_confirmed" ? "Email not confirmed" : "Invalid login credentials";
    return json({ error: code, message }, 400);
  }
  return json({ access_token: out.access_token, refresh_token: out.refresh_token });
});
