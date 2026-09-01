# Productivity Tracker - Project Notes for Future Agents

Single-file Korean-study/productivity web app for Kristoffer (Krox) and his
girlfriend Roxy. Main file: `index.html` (named that specifically so GitHub
Pages serves it at the domain root; it was called `korean_study_tracker.html`
in earlier sessions before the repo was properly linked up in this local
folder). A self-contained
Supabase (Postgres + Auth). "Core members" = Kristoffer & Roxy (hardcoded,
always-full sharing, no toggles). Everyone else who signs up is a regular
user with private data by default, unless they opt into the generalized
linking system (see below) to share with specific other people.

## Standing instructions (do these automatically, every session)

1. **After any edit to `index.html`, remind the user to push it to GitHub.**
   (The folder is now a proper git checkout tracked in GitHub Desktop, so
   "push" means the normal commit-and-push flow there, not copy-pasting
   into the github.com web editor.)
2. **SQL migrations — do NOT assume old migrations are still pending.**
   The user has said past migrations should be treated as already applied
   unless told otherwise. Only ever flag a migration as needing to be run
   when it was newly created or edited *in the current turn/session*. When
   that happens, use `AskUserQuestion` to ask whether it's been run yet —
   don't just state it as a reminder in prose. Do not re-ask about older
   `*_migration.sql` files that were only mentioned in past sessions.

## Architecture patterns to follow when extending the app

- **i18n**: `I18N.en` / `I18N.ko` / `I18N.vi` objects + `STATIC_MAP` (DOM id
  → i18n key) applied via `applyLanguage()`. For content with per-language
  variants stored on data objects (not just UI strings), the convention is
  suffixed fields: `field`, `field_ko`, `field_vi`, resolved via
  `const langSuffix = currentLang==='ko'?'_ko':currentLang==='vi'?'_vi':''; const val = (langSuffix && obj[field+langSuffix]) || obj[field];`
- **Privacy model**: Postgres `SECURITY DEFINER` functions expose
  aggregate-only data across RLS boundaries (e.g. `study_daily_totals()`,
  `reading_leaderboard()`, `job_leaderboard()`). Helper functions
  `is_core_member(uid)`, `current_is_core_member()`, and
  `shared_circle(a,b)` (`a=b OR (is_core_member(a) AND is_core_member(b))`)
  live in `privacy_rls_migration.sql` and are reused everywhere. Detailed
  personal data (books, jobs, study entries, grammar notes, writing samples)
  is always shared-read within the core circle, own-write only.
- **Viewer-scoped visibility** (e.g. "hide me from leaderboards"): use
  `shared_circle(auth.uid(), target_id)` in SQL WHERE clauses so a hidden
  user disappears from strangers' views but still appears to themselves and
  their core partner. Mirror this with a client-side
  `visibleOnLeaderboard(uid)` helper.
- **Mobile breakpoint**: `isMobileDevice(){ return window.innerWidth <= 640; }`,
  reused across mobile-specific branches (language dropdown vs buttons, etc).
  Debounced (150ms) `resize` listener re-runs mobile-dependent layout logic.
- **Verification discipline**: after any batch of HTML/JS edits, run a Node
  script via the shell that (a) extracts `<script>` blocks and runs
  `new Function(s)` per block for syntax validation, (b) cross-checks every
  `getElementById('X')` against actual `id="X"` attributes in the file, (c)
  spot-checks any newly touched STATIC_MAP id/key pairs or i18n keys.
- **Generalized linking system** (`link_groups_migration.sql`, built for
  task "let any user link up like Kristoffer & Roxy"): separate from and
  additive to the hardcoded core-member path — `is_core_member`/
  `shared_circle`/`amICore()` are untouched and still always give K&R full,
  non-toggleable sharing. Anyone else can form ONE link group at a time (up
  to 10 accepted members) via `link_invite`/`link_accept_invite`/
  `link_decline_invite`/`link_leave_group` RPCs (SECURITY DEFINER — all
  writes to `link_groups`/`link_group_members` go through these, never raw
  client inserts, so invite/cap semantics can't be bypassed). Each member
  independently controls, per data category, what THEY share with the rest
  of their group — categories: `study_entries`, `books`,
  `job_applications`, `grammar_notes`, `course_notes`, `writing_samples`,
  `recap`, `readiness`. `link_sharing_settings(user_id, target_user_id,
  category, enabled)`: a row where `target_user_id = user_id` is your own
  default (opt-out model, missing row = shared); a row where
  `target_user_id` = a specific groupmate's id is a per-partner override of
  that default for just them (the gear-icon panel next to their name in the
  roster). SQL helper `shared_circle_cat(a,b,cat)` resolves precedence
  override → default → true, and is used in the SELECT policies of the 6
  personal-log tables; the blanket `shared_circle(a,b)` was redefined to
  ALSO return true for any link-group pair (no category nuance — used for
  leaderboard-hide-override and `notebook_notes`, which don't have their
  own category). Client-side mirrors: `linkedPartnerIds()`,
  `visiblePartnersFor(category)` (category-aware list, used by recap/
  readiness/writing-sample filters), `visibleCircleMembers()` (blanket
  list, used by notebook filter), `mySharingSetting(cat)` (my default),
  `mySharingSettingFor(uid,cat)` (my override-or-default for one person),
  `isSharingWithMe(uid,cat)` (their override-or-default for me). UI is its
  own modal (`friendsModal`/`renderLinkedCircle()`), opened via a dedicated
  circle/people icon in the top-right icon row (left of the settings gear)
  — NOT inside account settings, that was tried and explicitly rejected.
  Red-dot pending-invite badge on that icon (`updateLinkNotifyDot()`).
  Deliberately did NOT extend the joint-calendar "assign event to my
  partner" / shared courses / synced daily-goal features beyond K&R — those
  are inherently 2-person UI concepts (single partner dropdown, one shared
  goal) that would need their own redesign to generalize to a 10-person
  group, and weren't part of the ask.
- **Course TA/RA flags** (`course_ta_ra_migration.sql`): `courses.is_ta` /
  `is_ra` booleans, deliberately independent of the `status` column
  (planning/signed_up/locked_in) — no interaction with the lock-in flow. You
  can be a TA/RA for a course whether or not you're also taking it. Not
  editable inline in the course list row — only settable via the "Add
  course" form and the course "Edit" panel (`buildCourseEditFieldsHtml`/
  `saveCourseEdit`), saved together with the rest of those forms' fields
  (no dedicated instant-toggle function). The TA/RA badge tag in the course
  row is colored in the course owner's personal color (`colorForUser`).
- **Sitewide "person filter" pattern**: a `<select>` populated by a
  `rebuildXPersonFilter()` function — one "All"/`t('allPeople')` option
  (always shown, even with only one other selectable person — "All" means
  "me + them combined," which is distinct from picking just their name)
  plus one `<option>` per visible person (`nameFor(uid)`), built from
  `[currentUser.id, ...visiblePartnersFor(category)]` or
  `[currentUser.id, ...visibleCircleMembers()]` for blanket (no-category)
  filters. Used by books/jobs/notes/writing/notebook tabs and by the
  calendar's who-filter (`calWhoFilterSelect`/`rebuildCalWhoFilter()`,
  replacing an earlier All/Me/Circle 3-button toggle) — sits inline on the
  same row as the Month/Week/Day view toggle, right-aligned, hidden
  entirely when the user has no core partner or linked circle.
- **Brand mark** (the goblet/two-facing-profiles icon in front of every
  "Productivity Tracker" `<h1>`, and the browser-tab favicon): the user's
  own raster artwork (`shared-time-header-280-website.png`), used verbatim —
  NOT redrawn or vector-traced. An earlier pass hand-traced the silhouette
  into an SVG approximation and got explicitly rejected ("why did you ruin
  the original logo... I told you to invert the colors"). Correct approach:
  dark-mode asset is the original PNG untouched; light-mode asset is a
  literal per-pixel RGB inversion of that same PNG (alpha channel left
  alone), not a palette-matched recolor — plain `PIL.ImageOps.invert` on the
  RGB channels. Both PNGs are embedded as base64 `data:image/png;base64,`
  URIs so the app stays a single file; each is defined ONCE in the `<style>`
  block as a `background-image` on `.brand-icon-dark`/`.brand-icon-light`
  (not repeated per usage — that would 4x the file bloat), and every
  `<h1>Productivity Tracker</h1>` spot just has two empty
  `<div class="brand-icon brand-icon-{light,dark}">` sized via inline
  width/height, wrapped in a `.brand-mark` flex row. Light/dark swap is
  CSS-only, keyed off the existing `body.dark` toggle (`display:none` /
  `display:block` pairs) — no JS needed. The favicon (`<link rel="icon"
  type="image/png">` in `<head>`) reuses the same original-PNG data URI,
  dark variant only (favicons can't respond to the in-app `body.dark` class).
  If asked to touch this mark again: don't redraw it, don't "smart" recolor
  it — only pixel-level operations on the source file the user provided,
  unless they explicitly ask for something else.
- **Certifications** (`certifications_migration.sql`, sibling feature to
  Jobs): the Jobs tab is now split into two sub-tabs, `jobsApplicationsSection`
  and `jobsCertificationsSection`, toggled via `jobsSubToggle`
  (`jobsSubApplicationsBtn`/`jobsSubCertificationsBtn`) and
  `switchJobsSubTab(view)` — the same `.cal-view-toggle`/button-row +
  `.hidden`-section pattern as Study's sub-tabs. Certifications is a full
  structural mirror of job_applications: own table (`name`, `issuer`,
  `status` in `in_progress`/`acquired`, `date_completed`, `link`), own
  `allCerts` client cache, own add form, own paginated list
  (`renderCerts()`, 3-preview/10-per-page, mirrors `renderJobs()`), own
  edit panel (`buildCertEditFieldsHtml`/`saveCertEdit`, status excluded —
  stays an always-visible dropdown, same split as jobs), and own public
  leaderboard (`certification_leaderboard()` SECURITY DEFINER function,
  aggregate acquired-count only, mirrors `job_leaderboard()`). Folded into
  the generalized linking system as a genuine new category
  (`'certifications'`, added to both the client `LINK_CATEGORIES` array and
  the SQL `link_sharing_settings.category` CHECK constraint) rather than a
  bespoke privacy mechanism, so the existing per-partner sharing-toggle
  "Friends" UI picks it up automatically. Both the Jobs and Certifications
  lists also got: a search bar (`jobSearchInput`/`certSearchInput`,
  filtering by company/certificate name) and a sort-mode `<select>`
  (`jobSortSelect`/`certSortSelect`, date vs status, using
  `JOB_STATUS_SORT_ORDER`/`CERT_STATUS_SORT_ORDER` maps) — both live
  alongside the existing person-filter dropdown on the "Your
  applications"/"Your certifications" card.
- **Writing feedback**: `writing_feedback` table (comments on a
  `writing_samples` row), gated on the same `writing_samples`-category
  visibility as the sample itself (own samples always visible to their
  owner). UI is a comment thread + textarea under the writing editor
  (`renderWritingFeedback()`/`sendWritingFeedback()`), own-comment delete
  only.
- **Yonsei tab** (`yonsei_boards_migration.sql`): the old top-level
  Courses and Notes tabs were merged into one new top-level tab,
  `panelYonsei` (`tabBtnYonsei`), which itself has three sub-tabs —
  Courses, Notes, and a new one, Boards — via the same
  `cal-view-toggle`/`.hidden`-section pattern as Study/Jobs
  (`yonseiSubToggle`, `switchYonseiSubTab(view)`, sections
  `yonseiCoursesSection`/`yonseiNotesSection`/`yonseiBoardsSection`). The
  original Courses/Notes markup and all its ids were moved as-is into the
  first two sections — no functional changes there. Boards is a
  best-effort pull of the public Yonsei GSIS "Official Notices" board (no
  login required): a direct browser `fetch()` to gsis.yonsei.ac.kr would be
  blocked by CORS, so `fetchYonseiBoards()` calls a Supabase Edge Function
  (`supabase/functions/fetch-yonsei-board`, deployed to the "Korean"
  Supabase project, `verify_jwt: false` since it's a read-only proxy of a
  public page), which fetches the board server-side and returns parsed
  JSON. The actual HTML parsing lives in the function's sibling module
  `supabase/functions/fetch-yonsei-board/parse.ts` (dependency-free, no
  Deno APIs; regex-matches on the board's real markup, `<a
  class="c-board-title">` anchors inside `.c-board-title-wrap`, date pulled
  from the following `.c-board-info-m` span), kept dependency-free
  specifically so it can be unit-tested outside the edge runtime (e.g. via
  `npx tsx` against a saved copy of the board HTML) without deploying
  first. If Yonsei changes their board layout, `parse.ts` is what needs
  retuning; re-fetch a fresh copy of the board HTML and check the
  anchor/date regexes still match. Only title + date are shown (no
  writer/number/attachments), title
  links out to the original post; error/empty state shows a direct link
  to the board instead. Fetched on-demand only (`fetchYonseiBoards()`,
  called from `switchYonseiSubTab` only when `view === 'boards'`, warm-cached
  after that), not eagerly in `renderAll()` like Courses/Notes, since it's
  a live network call. Personal display toggle (not a privacy/sharing
  setting — the feed is the same for everyone): `profiles.show_yonsei_boards`
  boolean, default true, mirrors the `hide_from_leaderboards` own-row
  pattern exactly (plain client `.update()`, no RPC, no new RLS policy
  needed). Client mirror: `showYonseiBoards`, settings checkbox
  `settingsShowYonseiBoards`, hides just the Boards sub-tab button
  (`updateYonseiBoardsVisibility()`), Courses/Notes stay visible
  regardless.

- **No emoji anywhere in the UI** (real-user rule: "I don't want standard
  emojis on the site"). An emoji is somebody else's artwork, at somebody
  else's weight, drawn differently by every OS. Icons come from `ICON.*` in
  the `svgIcon()` block: a 24-unit viewBox, `currentColor` stroke, 2px round
  caps, `class="ui-icon"` (which supplies the -0.15em baseline nudge that
  optically centres an inline SVG against text). Adding an icon means adding
  a path to `ICON_PATHS`, never reaching for a glyph. Two exceptions, both
  typographic rather than pictorial and both deliberate: the `✕` close/delete
  mark and the `★`/`☆` favourite pair. Watch for `.textContent` at any site
  being converted -- an SVG needs `.innerHTML` (this bit `applyDarkMode`).
- **Colour says what an action does**: `--danger` for anything that removes,
  `--edit` for anything that edits, applied through `.act-remove` /
  `.act-edit` on text buttons. Both are floored by MEASUREMENT, not by eye:
  the app's own link green holds 4.31:1 on a card. `--edit` is the one
  deliberate exception at 3.23:1, because it is not a fresh guess: **#a8790a
  is the `--edit` token from the Welcome Korea project** (`app/globals.css`),
  which Kristoffer pointed at directly, so the two apps agree on what an edit
  looks like. Take colours from there before inventing one.
  Three attempts missed first, and the lesson is which axis to move. Judged
  in OKLCH, the rejected ones were hue 60 (orange) and 83 (amber), both at
  L 0.53; I answered "too orange" by pushing hue to 100, which IS yellow but
  at that lightness reads olive. What separates gold from brown here is
  **lightness, not hue** -- the accepted #a8790a is hue 81, right next to the
  amber that was rejected, and works because it sits at L 0.61. The dark theme needs its own value for both:
  a yellow dark enough to read on paper is invisible on ink. Icon-only
  edit/delete buttons live inside containers that paint every button
  `--ink-soft`, so they need their own three-class rules to reach; move
  up/down arrows stay muted, being neither an edit nor a removal.
- **A short link's lifetime is tied to the file's**, not to the row that
  happens to reference it. `createShortLink(url, base, label, preferred)`
  takes an optional name typed at upload time and falls back to -2/-3 on a
  clash; `releaseShortLink(url)` MUST be called wherever a file is removed or
  REPLACED, or the name stays occupied by something no screen can reach
  (which is exactly what happened, and needed `pruneOrphanShortLinks()` to
  clear retroactively). That sweep only runs against a non-empty referenced
  set, since an offline or failed load would otherwise look like "nothing
  references anything" and delete every link the account has.

- **Quill (1.3.6) pastes by focusing a hidden div, and that moves the page.**
  `.ql-clipboard` is `position:absolute; top:50%` inside the editor, so
  `container.focus()` in `Clipboard.onPaste` scrolls the editor's MIDPOINT
  into view. Quill restores `quill.scrollingContainer.scrollTop` afterwards,
  but that defaults to the `.ql-editor` element -- which only scrolls if the
  editor is height-capped. The notes editors set `min-height` only, so they
  grow with the note and the PAGE is the scroller, and the restore is a
  no-op on the thing that moved. `keepPageStillOnPaste(quill)` must be
  called on every `new Quill(...)`; it overrides that one `focus()` with
  `{preventScroll:true}` (focus still lands, so the paste still arrives) and
  falls back to restoring the scroll by hand where the browser ignores the
  option. Measured 2418px of jump on a 4795px note before, 0 after.

- **A list re-render must not eat an open edit panel.** `renderAll()` runs on
  a 600ms-debounced realtime echo of ANY shared table, so `list.innerHTML =
  ''` routinely fires while someone is filling in a form -- including right
  after their own write echoes back. It throws away typed text and, worse,
  the chosen file, because an `<input type="file">` loses its `FileList` the
  instant the element is replaced (real-user report: "I have to select the
  file two times"). Both the course and job lists now lift any open
  `[data-*-edit-for]` panel out before the wipe and put the same node back
  after, listeners intact, guarded by a `data-*Wired` flag so the wiring pass
  does not attach every handler twice. Any future list with an inline edit
  form needs the same treatment.
- **A slug box previews the link it would create, never the word "auto".**
  `shortLinkPickerHtml(cls, from, base)` takes `from` because the two callers
  auto-name from different things: a course syllabus after the COURSE TITLE
  (so its preview follows the title field as it is typed), a job file after
  the FILE (so its preview fills in when one is chosen, via
  `syncFileChosenName`). Both run the same `slugify()` `createShortLink()`
  does, through `syllabusSlugBase()`, so a preview cannot promise a different
  address from the one that gets made.

- **All four inline edit panels go through `captureOpenPanels()` /
  `restoreOpenPanels()`** (courses, jobs, books, articles). Two conditions
  gate a restore, and both were learned by breaking them:
  1. The panel must still be OPEN. Save and Cancel both work by dropping the
     id from the expanded set and re-rendering, so restoring regardless puts
     the panel straight back and makes BOTH buttons look dead. The freshly
     built panel's own hidden state is the authority.
  2. The panel must be in the CURRENT language. A preserved node keeps the
     labels it was built with, so a language switch mid-edit would leave it
     in the old one until closed and reopened. Panels are stamped with
     `data-panel-lang` as they are wired.
  Any new list with an inline edit form should use the same two helpers
  rather than open-coding a third copy of this.

- **Books and articles are editable in place**, same shape as courses, jobs
  and certifications: an `act-edit` toggle in the row's meta line and a
  `notes-panel` below it. Status and pages-read stay OUT of those forms --
  they already have their own inline controls, and two controls for one
  field that can disagree is worse than the trip to the panel it saves.
  Shortening a book's page count pulls `pages_read` down with it, or the
  progress bar would read over 100%. Long text fields need `.field wide`
  (320px); the bare `.field` input is 150px, which truncates a title.

- **`data-ai-field` does double duty** on the book and article forms (add and
  edit alike): it marks a field for automatic recasing AND names it as a
  target the AI fill can write into, so one attribute keeps the two in step.
  `smartTitleCase` / `smartNameCase` fire on PASTE (the case they exist for)
  and on blur only when the value is entirely upper or entirely lower -- a
  strong signal it came from somewhere else. Deliberate mixed-case typing is
  never rewritten: **any word carrying a capital the writer put there is left
  alone** (eBay, iPhone, EU), which is what separates this from a naive title
  caser. An all-caps string carries no such signal, so there everything is
  recased and `KEEP_UPPERCASE` is the only thing saving the acronyms --
  extend that set rather than adding cleverness. Tokens with digits are never
  touched, which is what keeps "Vol. 20, No. 2, pp. 165-186, 1992" intact.
  Covered by 24 cases run in the browser; add to them before changing a rule.
- **"Fill from AI" is a clipboard round trip, not an API call.** It spends no
  key and needs no backend: Copy prompt puts a JSON-shaped request on the
  clipboard (seeded with whatever title is typed), you hand that to any LLM,
  and Paste details parses the answer back into the fields. The parser takes
  the first `{` to the last `}`, so code fences and chatter around the JSON
  are fine. `navigator.clipboard.readText()` can be refused outright, so
  every failure path falls back to a textarea rather than a dead button.

- **The header account pill shows the INITIAL below 640px, not a clipped
  name.** It used to get there with `max-width` on the real text, which shows
  the first letter plus whatever sliver of the second one fitted, at the
  row's small type. `setWhoName()` stores the full name on the element
  (`data-full-name`) and `applyWhoNameForWidth()` decides what to render;
  the debounced resize listener calls it, so it survives a rotation. The
  four places that set the name all go through `setWhoName()`.
  The NODE is deliberately unchanged: the colour picker and its click target
  hang off this same element, which is why the earlier fix clipped real text
  rather than using a pseudo-element (a `font-size:0` + `::before` version
  let the visible letter and the tappable box drift apart on iOS). With one
  letter as the content, the pill is a fixed 27px square -- measured to match
  what `.who .icon-btn` resolves to beside it, so the row stays one height.
  Compact, the tooltip carries the name, since it is nowhere else on screen.

## Migration files present (see folder for full current list)

All `*_migration.sql` (and other `.sql`) files now live in the `sql
migrations/` subfolder, not the project root — check there first.

Each `*_migration.sql` file in this folder is a Supabase migration written
during a past session. Treat them as already applied unless the user says
otherwise — do not proactively list them as "still pending." Only surface a
migration in chat (via AskUserQuestion) when it was written or changed in
the current session.

## Maintaining this file

Keep this file updated as new durable conventions, standing instructions, or
architectural decisions come up — this is the persistent memory future
agents/sessions should read first before making changes to the app.
