// Deletes every stored file whose owner's account no longer exists.
//
// Deleting an account (delete_own_account / admin_delete_user) removes the
// database rows, but storage cannot be emptied from SQL: a direct DELETE on
// storage.objects is refused, and would leave the file itself behind anyway.
// So a deleted user's CVs, syllabi and note images stayed online for good.
// The page calls this right after a deletion succeeds, and a daily cron job
// calls it too, so nothing is left behind even when that call is missed.
//
// It can only ever remove files in a folder named after an account id that
// is gone (orphaned_storage_objects() decides, in one query against
// auth.users), so anybody may trigger it. verify_jwt is off for that reason:
// the account that just deleted itself has no session left to send.

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
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const { data: orphans, error } = await admin.rpc("orphaned_storage_objects");
  if (error) {
    console.error("orphaned_storage_objects failed", error);
    return json({ error: "internal" }, 500);
  }
  const rows = (orphans ?? []) as { bucket_id: string; name: string }[];
  if (rows.length === 0) return json({ removed: 0 });

  // A brake, not a rule: if "orphaned" ever came back as most of storage,
  // something is wrong with the question, and deleting is the one thing that
  // cannot be taken back.
  const { data: count, error: countErr } = await admin.rpc("storage_object_total");
  if (countErr || typeof count !== "number") {
    console.error("storage_object_total failed", countErr);
    return json({ error: "internal" }, 500);
  }
  if (rows.length > 20 && rows.length > count / 2) {
    console.error(`refusing to remove ${rows.length} of ${count} files`);
    return json({ error: "refused" }, 409);
  }

  const byBucket = new Map<string, string[]>();
  for (const r of rows) {
    if (!byBucket.has(r.bucket_id)) byBucket.set(r.bucket_id, []);
    byBucket.get(r.bucket_id)!.push(r.name);
  }
  let removed = 0;
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const { data, error: rmErr } = await admin.storage.from(bucket).remove(names.slice(i, i + 100));
      if (rmErr) console.error(`remove from ${bucket} failed`, rmErr);
      removed += data?.length ?? 0;
    }
  }
  return json({ removed });
});
