-- ============================================================================
-- Adds per-user filtering on top of the Yonsei board notify system (see
-- yonsei_boards_notify_migration.sql for the base email-notification setup
-- this extends).
--
-- profiles.yonsei_hidden_subtags text[]: sub-tags (e.g. 'GCC', 'GCSD' --
-- course-code markers some Academics notices carry, distinct from the main
-- category) the user doesn't want to see on the Boards list OR be emailed
-- about, even if their notify category scope would otherwise include them.
-- Own-row-only, same pattern as show_yonsei_boards/notify_yonsei_board --
-- plain client .update(), no RPC. Defaults to {GCC,GCSD} hidden for every
-- account (including future signups), since these were called out as noise;
-- users can un-hide them from the Boards list UI.
--
-- profiles.notify_yonsei_categories text[]: which categories
-- (fetch-yonsei-board's canonical set -- 'Academics', 'Recruiting',
-- 'Admission', 'General Notice') trigger an email for this user, refining
-- the master notify_yonsei_board on/off switch. NULL means "all categories"
-- (the default -- so anyone who already opted in under the old all-or-
-- nothing behavior keeps getting everything unless they narrow it down).
--
-- notify_yonsei_board_new_items(items jsonb) is rewritten: items now arrive
-- from the edge function with {title,link,date,category,subTag} (category
-- is always a canonical string, never null -- see parse.ts's
-- canonicalCategory()), so the global new-item dedup (INSERT ... ON
-- CONFLICT ... RETURNING against yonsei_board_seen) is unchanged, but the
-- digest email is now built PER SUBSCRIBER instead of once for everyone:
-- each subscriber's own yonsei_hidden_subtags/notify_yonsei_categories
-- filters the shared "new this run" set down to what they actually want,
-- and if that comes out empty for them, no email is sent to them at all
-- (they may still get nothing back even though notify_yonsei_board is
-- true, if none of this run's new items match their scope).
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS yonsei_hidden_subtags text[] NOT NULL DEFAULT '{GCC,GCSD}';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS notify_yonsei_categories text[];

CREATE OR REPLACE FUNCTION notify_yonsei_board_new_items(items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  api_key text;
  item jsonb;
  v_article_no text;
  new_items jsonb := '[]'::jsonb;
  rec record;
  my_items jsonb;
  list_html text;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(items)
  LOOP
    v_article_no := substring(item->>'link' FROM 'articleNo=(\d+)');
    IF v_article_no IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO yonsei_board_seen (article_no)
    VALUES (v_article_no)
    ON CONFLICT (article_no) DO NOTHING;

    IF FOUND THEN
      new_items := new_items || jsonb_build_array(item);
    END IF;
  END LOOP;

  IF jsonb_array_length(new_items) = 0 THEN
    RETURN;
  END IF;

  SELECT decrypted_secret INTO api_key
  FROM vault.decrypted_secrets
  WHERE name = 'resend_api_key';

  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT u.email AS user_email, p.display_name, p.notify_yonsei_categories, p.yonsei_hidden_subtags
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.notify_yonsei_board = true
  LOOP
    SELECT jsonb_agg(elem) INTO my_items
    FROM jsonb_array_elements(new_items) elem
    WHERE NOT (coalesce(elem->>'subTag', '') = ANY(rec.yonsei_hidden_subtags))
      AND (rec.notify_yonsei_categories IS NULL OR (elem->>'category') = ANY(rec.notify_yonsei_categories));

    IF my_items IS NULL OR jsonb_array_length(my_items) = 0 THEN
      CONTINUE;
    END IF;

    list_html := (
      SELECT string_agg(
        '<li><a href="' || (elem->>'link') || '">' || (elem->>'title') || '</a> (' || (elem->>'date') || ')</li>',
        ''
      )
      FROM jsonb_array_elements(my_items) elem
    );

    PERFORM net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || api_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', 'Yonsei Notices <noreply@kristoffergt.com>',
        'to', rec.user_email,
        'subject', 'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(my_items) > 1 THEN 's' ELSE '' END),
        'html',
          '<p>Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
          '<p>New on the Yonsei GSIS Official Notices board:</p>' ||
          '<ul>' || list_html || '</ul>'
      )
    );
  END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION notify_yonsei_board_new_items(jsonb) TO service_role;
