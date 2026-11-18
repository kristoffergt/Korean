# The iPhone app

A SwiftUI shell around the site. The site itself (`index.html`) runs in one
web view and stays in charge of everything it already does; the app adds what
only a native app can:

- **The system's tab bar**, following the page's tabs (which are shown, their
  names, their marks, the language and the theme). The page's own floating
  bar is not drawn inside the app. Pressing the open tab again scrolls the
  page to its top. It keeps one size while the page scrolls (shrinking it
  with the page hung the app on a real iPhone). The bar steps aside while a
  dialog, the settings pages, the notifications page or the full-size chat
  cover the page.
- **Google sign-in** in the system's sign-in sheet (Google refuses to sign in
  inside an app's web view). The page asks Google itself for an ID token, as
  the website's own Google button does, so Google's screen names
  kristoffergt.com and not Supabase's address. The sheet ends on
  `/app-auth.html`, which hands the answer to `kristoffergt://auth`; the app
  gives it back to the page, which checks it and signs in with it.
- **Reminders** as the phone's own notifications: to-do reminders, the
  reminders written to the app in chat, and the reminders on calendar events
  you follow, for the next 35 days (iOS keeps at most 64 waiting, the app
  keeps 60). Pressing one opens the to-dos, the chat with the app, or the
  calendar on that day.
- **Widgets** (home screen and lock screen), drawn in the site's own colours
  and parts: Day, Up next, Week, Five weeks, To-do list, Today (study time
  against the goal), Year, and on iOS 27 Overview, a whole home screen page.
  Finished to-dos stay on, crossed out and greyed, under the open ones, and
  the calendars show each day's to-dos as one chip, done of all (green once
  all are done). They read a short summary the page writes into the app
  group whenever something changes, and move on to the next day by
  themselves at midnight. Hold a widget and choose **Edit Widget** to set
  what it shows:
  - To-do list: Today, Tomorrow, This week, This month, This year or Upcoming.
  - Day: the to-dos on or off, and the finished ones on or off.
  - Week and Five weeks: the to-dos on or off (off = events only).
  - Overview: the study time, the month, Up next and the week each on or off,
    and two lists (any of the above, or none).
- **A lock screen picture** (the Shortcuts action **Make Lock Screen
  Picture**). The lock screen only takes small widgets, so a bigger calendar
  goes on as the wallpaper: the action draws the calendar and to-dos over a
  photo at the phone's own size, below the clock. Layouts: Month and to-do
  lists, Week and today, Year and five weeks, Today and to-do lists, or A
  different one each time (each run shows the next of the layouts picked).
  It also takes the panels' colours, the two lists, and whether to leave
  room for the lock screen's own widgets under the clock.
- **Face ID lock** (Settings > Appearance > iPhone App), asking again after
  two minutes away.
- The **badge** on the icon (unread notifications and messages), **haptics**
  (the page's own buzzes, a ticked to-do, a row about to be swiped away),
  native alert/confirm/prompt dialogs, downloads handed to the share sheet,
  "Save as PDF" through the print sheet, other sites in an in-app Safari view,
  and an offline screen with Try again (also when iOS ended the page and it
  cannot load again).

## Running it

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put
   your team id in it (Xcode > Settings > Accounts shows it). That file is
   not committed.
2. Open `Tracker.xcodeproj`, pick the Tracker scheme and a simulator or your
   iPhone, and run.

A **Debug** build on the **Simulator** loads `http://localhost:8765/`, so
serve the repository there first:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory ..
```

A Debug build on a phone, and every Release build, loads
`https://kristoffergt.com/`. To point a build somewhere else, turn on the
`-TRBaseURL` argument in the scheme (Product > Scheme > Edit Scheme > Run >
Arguments) and change its address.

In a Debug build, the argument `-TRDrawLockPictures YES` draws every layout
of the lock screen picture from the widgets' sample day, dark and light, into
the app's `Documents/LockPictures` folder (on a simulator:
`xcrun simctl get_app_container booted com.kristoffergt.tracker data`).

Google sign-in needs `/app-auth.html` to be live on the site (it is the page
the sign-in sheet ends on), also when the app is pointed at a local server,
and `https://kristoffergt.com/app-auth.html` among the **Authorized redirect
URIs** of the site's web OAuth client in Google Cloud (APIs & Services >
Credentials). A provider that goes through Supabase instead also needs that
address in Supabase > Authentication > URL Configuration > Redirect URLs.

## Putting the picture on the lock screen

In Shortcuts, Automation > New Automation > Time of Day, pick a time and
Repeat Daily, Run Immediately, then add:

1. Find Photos (or Select Photos) for the photo underneath, if you want one;
   without one the picture is drawn on the site's soft green.
2. Make Lock Screen Picture: the photo, a layout, the lists.
3. Set Wallpaper Photo: the picture, on the Lock Screen of the wallpaper you
   use, with Show Preview and Crop to Subject turned off.

The wallpaper is only as fresh as the last run, so make several automations
(for example 06:00, 12:00, 18:00), each with its own layout, or one layout of
A different one each time. The app has to have been opened once after it is
installed before Shortcuts lists the action.

## Fonts in the widgets

The widgets use Inter, Noto Serif KR and Space Grotesk when their files are in
the widget target, and the phone's own faces otherwise. To use the site's
faces, add the `.ttf`/`.otf` files (all three are under the SIL Open Font
License) to `TrackerWidget/` with their licence; nothing else has to change.

## How the page and the app talk

Before the page's first line runs, the app defines `window.trackerNative`
(`platform: 'ios'`, `post(type, data)`). The page checks it once (`IN_APP` in
`index.html`), adds `in-app` to `<html>`, and from then on posts messages:
`hello`, `tabs`, `tab`, `theme`, `lang`, `chrome`, `barScale`, `haptic`, `oauth`,
`reminders`, `today`, `badge`, `setLock`, `askNotifications`, `openSettings`,
`share`, `print`. The app answers through `window.trackerShell.receive`
with `tab`, `reselect`, `go`, `oauthResult`, `oauthCancel`, `settings`, `insets`,
`printed`, `resume` and `resync`. Messages are taken only from the main frame
of the site's own pages.

## Known limits

- A reminder for something finished on another device still goes off on this
  phone until the app has been opened again (the app learns about changes
  from the page).
- If web push is also on for the same account on another device, both remind.
- Event reminders count back from the event's start on the phone's clock,
  08:00 for an event with no time, as the server's own reminders do.

## Later, with the paid developer programme

The personal team signs everything here (app groups included). These wait for
the paid programme:

- **Push notifications (APNs)**: an `aps-environment` entitlement, a device
  token sent to Supabase, and the `send-push` edge function learning to send
  to APNs beside web push. Local reminders can then stay as the offline copy.
- **Universal links**: `com.apple.developer.associated-domains` with
  `applinks:kristoffergt.com`, and `/.well-known/apple-app-site-association`
  on the site (Jekyll publishes dotfolders only when `_config.yml` includes
  them). Then the emails' links and `/f/` file links open in the app, and the
  sign-in sheet can end on an https address instead of `kristoffergt://`.
- **Sign in with Apple**: the capability, and Apple turned on as a provider in
  Supabase.
- **TestFlight**: an App Store Connect record for `com.kristoffergt.tracker`
  and its widget, then Product > Archive.
