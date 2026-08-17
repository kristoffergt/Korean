-- ============================================================================
-- Unified notification bell: one place aggregating every notification
-- source in the app (calendar reminders, Yonsei board notices, "someone
-- accepted your invite", and a one-off system announcement), with a
-- per-type email/in-app/both channel choice.
--
-- Design: this ADDS an in-app notification row alongside the existing email
-- sends rather than replacing them -- send_due_reminders() and
-- notify_yonsei_board_new_items() keep sending email exactly as before
-- (don't want to risk breaking already-working reminders), they just also
-- insert into `notifications` now, gated by notification_prefs.in_app
-- (default true when no pref row exists, so nobody's opted out by a schema
-- change they never made).
--
-- notification_prefs is deliberately NOT the gate for whether a
-- notification happens at all -- the existing feature-level opt-ins
-- (event_subscriptions existing, profiles.notify_yonsei_board) still decide
-- that, same as today. It only decides which channel(s) a notification that
-- would already happen goes out on.
--
-- Safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS notifications (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL, -- 'reminder' | 'yonsei_board' | 'link_accepted' | 'system'
  title text NOT NULL,
  body text,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx ON notifications(user_id, read_at);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select_own" ON notifications;
CREATE POLICY "notifications_select_own" ON notifications FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_update_own" ON notifications;
CREATE POLICY "notifications_update_own" ON notifications FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
-- No INSERT policy -- every insert goes through create_notification() (for
-- cross-user cases like link-accept) or directly from the existing
-- SECURITY DEFINER email functions below (already trusted, run as the
-- function owner).

CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type text NOT NULL,
  email boolean NOT NULL DEFAULT true,
  in_app boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, type)
);
ALTER TABLE notification_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notification_prefs_select_own" ON notification_prefs;
CREATE POLICY "notification_prefs_select_own" ON notification_prefs FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notification_prefs_upsert_own" ON notification_prefs;
CREATE POLICY "notification_prefs_upsert_own" ON notification_prefs FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "notification_prefs_update_own" ON notification_prefs;
CREATE POLICY "notification_prefs_update_own" ON notification_prefs FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Whether `target_user_id` wants in-app notifications of `ntype` -- true
-- (the default) unless they've explicitly turned it off.
CREATE OR REPLACE FUNCTION wants_in_app_notification(target_user_id uuid, ntype text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT in_app FROM notification_prefs WHERE user_id = target_user_id AND type = ntype), true);
$$;

-- Cross-user insert (e.g. the invitee's accept action notifying the
-- inviter) -- can't go through a plain RLS-scoped client insert since the
-- caller and the recipient are different people.
CREATE OR REPLACE FUNCTION create_notification(target_user_id uuid, ntype text, ntitle text, nbody text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT wants_in_app_notification(target_user_id, ntype) THEN
    RETURN;
  END IF;
  INSERT INTO notifications(user_id, type, title, body) VALUES (target_user_id, ntype, ntitle, nbody);
END;
$$;
REVOKE EXECUTE ON FUNCTION create_notification(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_notification(uuid, text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION mark_notification_read(notification_id bigint)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE notifications SET read_at = now() WHERE id = notification_id AND user_id = auth.uid() AND read_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION mark_notification_read(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mark_notification_read(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE notifications SET read_at = now() WHERE user_id = auth.uid() AND read_at IS NULL;
$$;
REVOKE EXECUTE ON FUNCTION mark_all_notifications_read() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read() TO authenticated;

CREATE OR REPLACE FUNCTION set_notification_pref(ntype text, p_email boolean, p_in_app boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notification_prefs(user_id, type, email, in_app)
  VALUES (auth.uid(), ntype, p_email, p_in_app)
  ON CONFLICT (user_id, type) DO UPDATE SET email = excluded.email, in_app = excluded.in_app;
END;
$$;
REVOKE EXECUTE ON FUNCTION set_notification_pref(text, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION set_notification_pref(text, boolean, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed the bell from link_accept_invite() -- "X accepted your invite" now
-- lands here too, alongside the accept_notified badge already added in
-- link_accept_notification_migration.sql (kept as-is; this is additive).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION link_accept_invite()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
  my_group uuid;
  member_count integer;
  inviter_id uuid;
  my_name text;
BEGIN
  SELECT group_id, invited_by INTO my_group, inviter_id FROM link_group_members WHERE user_id = me AND status = 'pending';
  IF my_group IS NULL THEN
    RAISE EXCEPTION 'No pending invite to accept';
  END IF;
  SELECT COUNT(*) INTO member_count FROM link_group_members
    WHERE group_id = my_group AND status = 'accepted';
  IF member_count >= 10 THEN
    RAISE EXCEPTION 'That link group is already at the 10-member limit';
  END IF;
  UPDATE link_group_members SET status = 'accepted', responded_at = now(), accept_notified = false WHERE user_id = me;
  IF inviter_id IS NOT NULL THEN
    SELECT display_name INTO my_name FROM profiles WHERE id = me;
    PERFORM create_notification(inviter_id, 'link_accepted', COALESCE(my_name, 'Someone') || ' accepted your invite');
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION link_accept_invite() TO authenticated;

-- ---------------------------------------------------------------------------
-- Feed the bell from send_due_reminders() -- additive insert right after
-- the existing email send, same reminder_log dedupe guard so it only fires
-- once per due reminder, never re-added on re-runs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_due_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  api_key text;
  rec record;
  occ date;
  occ_ts timestamptz;
  target_ts timestamptz;
  window_start timestamptz := now() - interval '35 minutes';
  window_end timestamptz := now();
  reminder jsonb;
begin
  select decrypted_secret
    into api_key
  from vault.decrypted_secrets
  where name = 'resend_api_key';

  if api_key is null then
    raise notice 'No Resend API key found in vault';
    return;
  end if;

  for rec in
    select
      es.id as sub_id,
      es.user_id,
      es.reminders,
      ev.title,
      ev.event_date,
      ev.event_time,
      ev.recur_freq,
      ev.recur_interval,
      ev.recur_end_type,
      ev.recur_end_date,
      u.email as user_email,
      p.display_name
    from event_subscriptions es
    join events ev on ev.id = es.event_id
    join auth.users u on u.id = es.user_id
    left join public.profiles p on p.id = es.user_id
  loop
    occ := next_occurrence(
      rec.event_date,
      rec.recur_freq,
      coalesce(rec.recur_interval, 1),
      rec.recur_end_type,
      rec.recur_end_date
    );

    if occ is null then
      continue;
    end if;

    occ_ts :=
      (occ::timestamp + coalesce(rec.event_time, '09:00:00'::time))
      - interval '9 hours';

    for reminder in
      select * from jsonb_array_elements(rec.reminders)
    loop
      if (reminder->>'unit') = 'hours' then
        target_ts :=
          occ_ts - ((reminder->>'value')::int || ' hours')::interval;
      else
        target_ts :=
          occ_ts - ((reminder->>'value')::int || ' days')::interval;
      end if;

      if target_ts > window_start
         and target_ts <= window_end then

        if not exists (
          select 1
          from reminder_log
          where subscription_id = rec.sub_id
            and occurrence_date = occ
            and reminder_value = (reminder->>'value')::int
            and reminder_unit = (reminder->>'unit')
        ) then

          perform net.http_post(
            url := 'https://api.resend.com/emails',
            headers := jsonb_build_object(
              'Authorization', 'Bearer ' || api_key,
              'Content-Type', 'application/json'
            ),
            body := jsonb_build_object(
              'from', 'Calendar Reminders <noreply@kristoffergt.com>',
              'to', rec.user_email,
              'subject', 'Reminder: ' || rec.title,
              'html',
                '<p>Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
                '<p>Here''s a reminder for "<strong>' || rec.title || '</strong>" on ' ||
                to_char(occ, 'YYYY-MM-DD') ||
                case
                  when rec.event_time is not null
                  then ' at ' || to_char(rec.event_time, 'HH12:MI AM') || ' KST'
                  else ''
                end ||
                '.</p>'
            )
          );

          if wants_in_app_notification(rec.user_id, 'reminder') then
            insert into notifications(user_id, type, title, body)
            values (rec.user_id, 'reminder', 'Reminder: ' || rec.title, to_char(occ, 'YYYY-MM-DD'));
          end if;

          insert into reminder_log (
            subscription_id,
            occurrence_date,
            reminder_value,
            reminder_unit
          )
          values (
            rec.sub_id,
            occ,
            (reminder->>'value')::int,
            reminder->>'unit'
          );

        end if;
      end if;
    end loop;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Feed the bell from notify_yonsei_board_new_items() -- additive insert
-- alongside the existing email send, one notification per affected user
-- summarizing the new item count (not one row per item -- a board update
-- can carry several).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_yonsei_board_new_items(items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  api_key text;
  item jsonb;
  v_article_no text;
  new_items jsonb := '[]'::jsonb;
  rec record;
  my_items jsonb;
  list_html text;
  recipient_id uuid;
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
    SELECT p.id AS recipient_id, u.email AS user_email, p.display_name, p.notify_yonsei_categories, p.yonsei_hidden_subtags
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

    IF wants_in_app_notification(rec.recipient_id, 'yonsei_board') THEN
      INSERT INTO notifications(user_id, type, title, body)
      VALUES (
        rec.recipient_id, 'yonsei_board',
        'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(my_items) > 1 THEN 's' ELSE '' END),
        (SELECT string_agg(elem->>'title', ', ') FROM jsonb_array_elements(my_items) elem)
      );
    END IF;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------------
-- One-time system announcement to every existing account about the new
-- site sign-up/sign-in PIN (site_pin_gate_migration.sql) -- they signed up
-- before the gate existed, so this is the only way they'd otherwise learn
-- their own PIN is now required (visible in Settings, per that migration).
-- Not wrapped in a reusable function since it's a one-off backfill, not an
-- ongoing trigger; safe to re-run (ON CONFLICT would need a natural key to
-- dedupe on, so instead this only inserts for users who don't already have
-- a 'system' notification with this exact title).
-- ---------------------------------------------------------------------------
INSERT INTO notifications(user_id, type, title, body)
SELECT p.id, 'system', 'New site PIN required for sign-in',
  'Signing in or creating an account now requires a 4-digit site PIN. Find it anytime in Settings.'
FROM profiles p
WHERE NOT EXISTS (
  SELECT 1 FROM notifications n
  WHERE n.user_id = p.id AND n.type = 'system' AND n.title = 'New site PIN required for sign-in'
);
