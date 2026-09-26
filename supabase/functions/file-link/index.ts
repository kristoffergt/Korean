// Resolves one short file link (kristoffergt.com/f/<slug>) to a URL that
// opens the file for the next hour. Called by 404.html, signed out.
//
// It exists so the file itself does not have to be public. file_links used to
// be readable by anyone signed out, and read without a filter it listed every
// CV and cover letter URL in the app, straight out of a public bucket. Now the
// table is only readable by its owner, the CV bucket is private, and the only
// way in from outside is to name a slug: this answers for that one slug and
// no other, with a signed URL rather than a permanent one.
//
// verify_jwt is off: the visitor has no session, and the slug is the whole
// point of a link somebody was sent.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const STORAGE_PREFIX = `${SUPABASE_URL}/storage/v1/object/public/`;
const SIGNED_TTL_SECONDS = 3600;

const ALLOWED_ORIGINS = ["https://kristoffergt.com", "https://www.kristoffergt.com"];
function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const ok = ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return ok
    ? {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Vary": "Origin",
    }
    : { "Vary": "Origin" };
}

Deno.serve(async (req) => {
  const cors = corsFor(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "GET") return json({ error: "GET only" }, 405);

  const slug = (new URL(req.url).searchParams.get("slug") || "").toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(slug)) return json({ error: "not_found" }, 404);

  const { data: row } = await admin.from("file_links").select("url, label").eq("slug", slug).maybeSingle();
  if (!row || typeof row.url !== "string" || !row.url.startsWith(STORAGE_PREFIX)) {
    return json({ error: "not_found" }, 404);
  }
  // <bucket>/<percent-encoded path>, exactly as getPublicUrl wrote it.
  const rest = row.url.slice(STORAGE_PREFIX.length).split("?")[0].split("#")[0];
  const slash = rest.indexOf("/");
  if (slash < 1) return json({ error: "not_found" }, 404);
  const bucket = rest.slice(0, slash);
  let path: string;
  try { path = decodeURIComponent(rest.slice(slash + 1)); } catch { path = rest.slice(slash + 1); }

  const { data: signed, error } = await admin.storage.from(bucket).createSignedUrl(path, SIGNED_TTL_SECONDS);
  if (error || !signed?.signedUrl) return json({ error: "not_found" }, 404);
  return json({ url: signed.signedUrl, label: row.label ?? null, name: path.split("/").pop() ?? null });
});
