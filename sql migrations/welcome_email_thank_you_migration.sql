-- ============================================================================
-- The welcome email becomes a thank-you for signing up, and it actually sends.
--
-- 1. IT NEVER ARRIVED. It was the only email sent from
--    noreply@reminders.kristoffergt.com, and Resend refuses that domain
--    ("The reminders.kristoffergt.com domain is not verified", 403, seen in
--    net._http_response for both sign-ups on 29 Sep). Every other email the
--    app sends uses noreply@kristoffergt.com, so this one does too now. The
--    admin copy had the same sender and went nowhere either.
--
-- 2. IT LOOKS LIKE THE SIGN-UP EMAILS. The one somebody gets right before this
--    is Supabase's "Confirm signup" (supabase/email-templates/), so the markup
--    is that template's: the icon beside the name in the dark bar, a bold
--    title, the green button, a muted note, and the same footer line.
--
-- 3. IT IS IN THE LANGUAGE THEY SIGNED UP IN. raw_user_meta_data->>'locale'
--    is 'ko', 'vi', or anything else (English), which is the rule the
--    confirm-signup template already follows. An email sign-up puts it there
--    in signUp(); a Google sign-up now gets it from ensureProfileExists()
--    in index.html, which writes it just before inserting this row.
--
-- 4. A GOOGLE ACCOUNT IS NOT TOLD ABOUT ITS PASSWORD. It has none, so the note
--    says to use "Continue with Google" with that address instead.
--
-- Fires on profiles INSERT (on_profile_created, unchanged). ensureProfileExists()
-- upserts, and an upsert that hits an existing row fires AFTER UPDATE rather
-- than AFTER INSERT, so nobody gets this twice.
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_welcome_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  api_key text;
  user_email text;
  loc text;
  provider text;
  via_google boolean;
  nm text;
  em text;
  subject text;
  title text;
  intro text;
  saved text;
  button_label text;
  signin_note text;
  footer text;
  body_html text;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';
  select u.email,
         case when u.raw_user_meta_data->>'locale' in ('ko', 'vi') then u.raw_user_meta_data->>'locale' else 'en' end,
         coalesce(u.raw_app_meta_data->>'provider', 'email')
    into user_email, loc, provider
    from auth.users u where u.id = new.id;

  if api_key is null or user_email is null then
    return new;
  end if;

  via_google := provider = 'google';
  nm := html_escape(coalesce(new.display_name, ''));
  em := html_escape(user_email);

  if loc = 'ko' then
    subject := 'Productivity Tracker에 가입해 주셔서 감사합니다';
    title := '가입해 주셔서 감사합니다';
    intro := nm || '님, Productivity Tracker에 오신 것을 환영합니다. 계정을 바로 사용할 수 있습니다.';
    saved := '추가한 모든 내용은 계정에 저장되므로, 로그인하는 어느 기기에서나 볼 수 있습니다.';
    button_label := 'Productivity Tracker 열기';
    signin_note := case when via_google
      then '로그인할 때는 <strong>' || em || '</strong> 계정으로 &ldquo;Google로 계속하기&rdquo;를 누르세요.'
      else '로그인할 때는 이메일 또는 이름과 비밀번호를 입력하세요. 비밀번호를 잊으셨다면 로그인 화면에서 &ldquo;비밀번호를 잊으셨나요?&rdquo;를 누르세요.'
    end;
    footer := 'Productivity Tracker · kristoffergt.com · 이 메일은 자동으로 발송되었으며 직접 회신하지 마세요.';
  elsif loc = 'vi' then
    subject := 'Cảm ơn bạn đã đăng ký Productivity Tracker';
    title := 'Cảm ơn bạn đã đăng ký';
    intro := 'Xin chào ' || nm || ', chào mừng bạn đến với Productivity Tracker. Tài khoản của bạn đã sẵn sàng để sử dụng.';
    saved := 'Mọi thứ bạn thêm đều được lưu vào tài khoản, nên bạn có thể xem chúng trên bất kỳ thiết bị nào bạn đăng nhập.';
    button_label := 'Mở Productivity Tracker';
    signin_note := case when via_google
      then 'Để đăng nhập, hãy bấm &ldquo;Tiếp tục với Google&rdquo; bằng tài khoản <strong>' || em || '</strong>.'
      else 'Để đăng nhập, hãy nhập email hoặc tên hiển thị và mật khẩu của bạn. Quên mật khẩu? Hãy bấm &ldquo;Quên mật khẩu?&rdquo; trên màn hình đăng nhập.'
    end;
    footer := 'Productivity Tracker · kristoffergt.com · Đây là email tự động, vui lòng không trả lời trực tiếp.';
  else
    subject := 'Thanks for signing up to Productivity Tracker';
    title := 'Thanks for signing up';
    intro := 'Hi ' || nm || ', and welcome to Productivity Tracker. Your account is ready to use.';
    saved := 'Everything you add is saved to your account, so it is there on any device you sign in on.';
    button_label := 'Open Productivity Tracker';
    signin_note := case when via_google
      then 'To sign in, use &ldquo;Continue with Google&rdquo; with <strong>' || em || '</strong>.'
      else 'To sign in, use your email or username and your password. Forgot it? Use &ldquo;Forgot password?&rdquo; on the sign-in screen.'
    end;
    footer := 'Productivity Tracker · kristoffergt.com · This is an automated message, please don''t reply directly to it.';
  end if;

  -- The confirm-signup template's markup, verbatim apart from the text.
  body_html :=
    '<div style="background:#F5F5F6;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,''Inter'',Helvetica,Arial,sans-serif;">' ||
      '<div style="max-width:480px;margin:0 auto;background:#ffffff;border:1px solid #E1E1E3;border-radius:12px;overflow:hidden;">' ||
        '<div style="background:#1E1F22;padding:20px 28px;">' ||
          '<img src="https://kristoffergt.com/icon-192.png" width="24" height="24" alt="" style="vertical-align:middle;border-radius:6px;margin-right:8px;display:inline-block;" />' ||
          '<span style="font-family:Georgia,''Noto Serif KR'',serif;color:#F5F5F6;font-size:18px;font-weight:bold;letter-spacing:0.02em;vertical-align:middle;">Productivity Tracker</span>' ||
        '</div>' ||
        '<div style="padding:28px;color:#1E1F22;font-size:15px;line-height:1.65;">' ||
          '<p style="margin:0 0 16px;font-size:20px;font-weight:bold;">' || title || '</p>' ||
          '<p style="margin:0 0 12px;">' || intro || '</p>' ||
          '<p style="margin:0 0 20px;">' || saved || '</p>' ||
          '<div style="margin:0 0 24px;">' ||
            '<a href="https://kristoffergt.com" style="display:inline-block;background:#4F7563;color:#ffffff;text-decoration:none;padding:11px 24px;border-radius:6px;font-size:15px;font-weight:600;">' || button_label || '</a>' ||
          '</div>' ||
          '<p style="margin:0;color:#6B6D72;font-size:13px;">' || signin_note || '</p>' ||
        '</div>' ||
        '<div style="padding:16px 28px;border-top:1px solid #EFEFEF;color:#6B6D72;font-size:12px;">' || footer || '</div>' ||
      '</div>' ||
    '</div>';

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', 'Productivity Tracker <noreply@kristoffergt.com>',
      'to', user_email,
      'subject', subject,
      'html', body_html
    )
  );

  -- The admin copy stays in English and says how and in which language they
  -- signed up, which the old one did not.
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', 'Productivity Tracker <noreply@kristoffergt.com>',
      'to', 'kristoffergt@gmail.com',
      'subject', 'New signup: ' || coalesce(new.display_name, user_email),
      'html', email_shell(
        'Internal notification: a new account was created.',
        '<p style="margin:0 0 6px;">New account created.</p>' ||
        '<p style="margin:0;color:#6B6D72;">Name: ' || nm || '<br>Email: ' || em ||
        '<br>Signed up with: ' || case when via_google then 'Google' else 'email' end ||
        '<br>Language: ' || loc || '</p>'
      )
    )
  );

  return new;
end;
$function$;

-- A trigger function is never called directly, so nobody needs EXECUTE on it.
REVOKE EXECUTE ON FUNCTION public.send_welcome_email() FROM PUBLIC, anon, authenticated;
