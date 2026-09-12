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

1. **COMMIT the work yourself; the user pushes.** (Changed 4 Sep, superseding
   both "remind the user to push" and the older "suggest a commit title he
   can paste into GitHub Desktop" -- do neither now, just commit.) Same
   message style as before: short, imperative, describing what changed.
   Never push, and never commit on a dirty tree you did not create.
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

- **A user-entered URL never goes straight into an `href`.** `safeExternalUrl()`
  unwraps what people and LLMs actually paste (`[label](target)` Markdown,
  `<url>`, quoted forms), adds a scheme when there is none, and returns null
  for anything that cannot be made into an http(s) URL. Two failures made it
  necessary, and the second is the one to remember: **a URL with no scheme is
  RELATIVE**, so "doi.org/..." opened as kristoffergt.com/doi.org/... .
  Refusing every other scheme is also what keeps `javascript:` out of an href
  on rows a circle can write. Parentheses are deliberately never stripped --
  a DOI can end in one (0305-750X(92)90097-F).
  Render through `externalLinkHtml()`, which falls back to plain text when
  the value is not a link, so a bad paste is visibly not a link rather than a
  broken one. It runs at render time, so rows saved before this self-heal on
  screen; the six save paths (article/job/cert, add and edit) repair the
  stored value too, for the case where a field is pasted into and saved
  without ever losing focus. 13 cases are checked in the browser.

- **Never open a native picker with `.click()` on an element in a hidden
  subtree.** The header pill used to call `.click()` on `#myColorPicker`,
  which lives inside the Account settings MODAL (`display:none`). That works
  well enough in desktop Chrome to look fine and does nothing at all on iOS,
  so the control was dead in the installed app while testing clean on a
  laptop. The fix is the pattern `.who .lang-switch-select` already used: lay
  the real `<input type="color">` over the pill at `opacity:0`, so the tap
  lands on a native control and needs no synthesised gesture. Verify with
  `document.elementFromPoint()` at the pill's centre, not by calling
  `.click()` in a console -- that proves the wrong thing.
  Two inputs now write the colour (header and settings), so they share
  `applyMyColor()` and `setMyColorInputs()` keeps them in step.
- **Watch `clamp()` with a vw middle term on small viewports.** The header
  globe was `clamp(10px,1.6vw,14px)`, which at 375px resolves to the FLOOR --
  10px, two thirds of every other icon in the row, and in `--ink-soft` on top
  of that. Header icons are a flat 15px in `--ink`; a vw-scaled icon in a row
  of fixed ones will always drift at one end of the range.

- **The day view enlarges the class number; the week view must not.** Both go
  through `renderCalGrid(dates)`, so `dates.length === 1` is what
  distinguishes them. The code renders at 18px against the 9px every other
  detail line uses, and is split out of the shared `code · concentration`
  line so the concentration is not scaled with it.
  An event bar is `overflow:hidden`, so **the order of the lines is the
  priority order** -- whatever sits last is what gets cut. Enlarging the code
  in its original fourth position simply clipped it in half, which is bigger
  AND less readable. Enlarged, the order is class number, room, professor,
  concentration. Two guards keep it to bars with the room for it: not when
  the bar shares its column with an overlapping class, and not under 44px
  tall (58 where the mobile layout reserves 14px above the title).

- **The TOPIK countdown is the test day only.** The "registration opens in"
  tile is gone (real-user request); its calendar EVENT and 1-day reminder
  are deliberately kept, since those still tell you when to sign up. The
  venue is `events.location` on the TOPIK test row, not a profile field:
  a location belongs to one sitting, so a new cycle creates a new event and
  starts blank instead of carrying last cycle's venue forward. The input is
  hidden until that event exists, or there would be nothing to save onto and
  what you typed would vanish; and a re-render (the card ticks every 30s)
  skips the value while the field has focus, or it would overwrite you
  mid-word. Events are read with `select('*')`, so the new column needs no
  query change.

- **The active tab is one element that travels** (`.tab-slider`), not a fill
  each tab paints. It applies to every row in `SLIDER_ROWS` -- the main tab
  bar and the six `.cal-view-toggle` sub-tab rows -- and is driven by a
  MutationObserver per row rather than by hooking each switch function:
  seven rows have their own switchers, plus deep links and notification
  navigation that set the active button directly, and an observer cannot
  fall out of step with a route added later.
  **The opt-in rules must come after EVERY row's own `.active` rule.**
  `.has-slider > button.active` and `.cal-view-toggle button.active` both
  score (0,2,1), so source order decides; written earlier, the active
  sub-tab kept painting its own ink fill on top of the travelling pill.
  A row inside a hidden panel measures 0 and stays UNPARKED so it places
  itself the moment it is visible; `refreshRowSliders(false)` is what does
  that, called both when a panel is shown and after any sub-tab change,
  since a section can carry a row of its own.
  Three more things that are easy to get wrong:
  1. **The tabs it passes must not be opaque**, or the pill is invisible
     mid-flight. That treatment is gated on `.slider-ready`, which
     `moveRowSlider()` adds only once the pill has really been PLACED --
     not on `.has-slider`, which merely says the row opted in. An active
     button is painted in `--paper` (near white) and is legible only against
     the pill behind it, so a row that could not measure itself (inside a
     closed modal) rendered white text on a light background and the tab was
     invisible. The class comes back off whenever the row stops being
     measurable, so light-on-light cannot happen.
  2. **width is written, not `scaleX`.** These are 6px-radius pills, and
     scaling a rounded box stretches the corners into ellipses.
  3. **The first placement is not a journey** -- it jumps, guarded by
     `no-slide-anim` plus a forced reflow, or the pill sails in from the
     left edge on load. Same reasoning as an element not transitioning from
     nothing.
  `reorderMobileTabs()` wraps `reorderMobileTabsInner()` so the pill
  re-measures after EVERY relayout: that body has four early returns, and
  the row's geometry changes in all of them.
- **Verifying an animation in the preview pane needs care.** A hidden pane
  freezes CSS transitions at their start value, so `getBoundingClientRect()`
  reads the OLD position however long you wait, and a working slide looks
  broken. Prove the target geometry by disabling the transition
  (`no-slide-anim`) and measuring, and prove the motion with successive
  screenshots, which force the pane to paint.

- **A month cell has about 30px of content width**, which is the constraint
  behind three separate faults found in one screenshot of the expense
  calendar:
  1. `.event-chip{padding-right:12px !important}` reserved room for
     `.chip-initial`, which ONLY the personal calendar's chips carry. With
     `!important` nothing could opt out, so an expense chip lost a fifth of
     its width to a badge that was not there and read as "B..." / "C...".
     Scoped with `:has(> .chip-initial)` now.
  2. A full "₩100,000" cannot fit at any readable size and was clipped
     mid-glyph. `expFormatMoneyCompact()` abbreviates from a THOUSAND up
     (₩8k, ₩117k, ₩1.3M), with a decimal only under ten so the string
     never exceeds five characters, and the exact figure in the `title`.
     Watch the tier boundary: 999,999 divided by a thousand rounds to
     "1000k", so the tier is re-picked from the rounded figure.
  3. `.month-nav button` had no background of its own and fell through to
     the global `button{background:var(--ink)}` -- near-black in the light
     theme, which looked deliberate, and near-WHITE in the dark one, where
     the arrows read as two blank blocks. Any bare `<button>` inherits that
     solid fill; give it a style or it will surprise you in one theme.
  When checking for clipping, compare `scrollWidth > clientWidth` exactly --
  a `+1` tolerance hid a genuine one-pixel overflow that rendered as an
  ellipsis.

- **A category can be parked out of the expense totals**, by clicking its row
  in the breakdown (real-user request: "so you can see averages and totals
  without those"). `expMutedCategories` is a plain Set that is deliberately
  NOT persisted or synced -- "temporarily" is the point, and a filter that
  survives a reload is how a total quietly lies to you a fortnight later.
  Everything that adds money up goes through `expCountedExpenses()`, so the
  stat tiles, the day totals in the month grid and the breakdown's own
  percentages cannot disagree about what is in play; percentages are of the
  COUNTED total, so what is left still sums to 100. A parked row keeps its
  amount, is faded rather than removed, and says "not counted"; the chips in
  the grid fade with it but stay, since an excluded expense still happened.
  A reset appears only while something is parked -- the same rule the rest of
  the app follows, so a filter can never be hiding money with nothing on
  screen to say so.

- **Who is online, and texting your circle**, both under the circle button.
  Presence is a single Realtime channel joined for the session
  (`ensureOnlinePresence`): nothing is written, going offline is the socket
  closing, and the circle filter is applied on the CLIENT, so the channel
  itself carries only a user id. Two Realtime rules cost real time to find:
  presence callbacks must be registered BEFORE `subscribe()` or the client
  never keeps the state at all, and supabase-js returns an EXISTING channel
  for a topic rather than a new one, so a stale one has to be removed first
  or `.on()` throws -- out of `onAuthed()`, which is why the whole setup is
  wrapped in a try/catch. A missing dot must never be a failed sign-in.
- **Messaging lives in its own dock, bottom-right** (`#chatDock`), not in
  the circle settings modal -- texting is something you do while using the
  app, not a preference you go and find (real-user request). The dock is
  also where presence is shown, since who is about is what makes you want to
  say something. It is hidden entirely for a guest or an empty circle, so it
  is never a button that opens an empty room.
- **A new realtime table MUST be added to the `supabase_realtime`
  publication.** `postgres_changes` on a table outside it delivers NOTHING,
  and the subscription still reports SUBSCRIBED -- so the failure is
  completely silent and reads as a client bug. That is what made messages
  need a refresh to appear. Check with
  `select tablename from pg_publication_tables where pubname='supabase_realtime'`
  whenever live updates "don't work"; every other realtime table here is
  already in it.
- **Enter in a chat box must respect the IME.** Two rows were landing 1ms
  apart for one send -- the full message and then just its last word -- which
  is what an IME leaves behind: Enter is seen once while a word is still
  composing, and again after the keyboard commits that word back into the
  box. Guard on `compositionstart`/`compositionend`, `e.isComposing` AND
  `keyCode === 229`, and keep a single-flight flag so a second concurrent
  send is impossible whatever caused it. The DB is what proved this: pairs
  1ms apart with different lengths, not a human sending twice.
- **Attachments use the project's ONLY private bucket**
  (`circle-attachments`). Every other bucket here is public, which is an
  accepted trade for syllabi and CVs; these are private messages, so files
  are reached through short-lived signed URLs and the storage read policy
  repeats the MESSAGE's own visibility predicate rather than guessing at it
  again. Signed URLs are minted one batch per render and cached until they
  are nearly expired. An image that cannot load (expired URL, deleted
  object, offline) falls back to the same named card a non-image gets --
  without it a failure is an EMPTY bubble with no clue what was in it.
- **Search and the files view run on the SERVER**, which is the whole point:
  they reach past the 300-message window the client holds, so "go further
  back by searching" actually does. Body search is ILIKE over a pg_trgm
  index (short chat text, people search fragments, stemming would not help);
  the files view is a partial index on messages that have an attachment. A
  date filter's end day is `T23:59:59.999`, not midnight, or the last day
  you pick is excluded.
- **Bubbles are tinted with the SENDER'S own colour**, the one their name
  wears everywhere else, rather than one colour for me and one for everyone
  else -- the colour at low alpha with a solid edge, so it stays legible in
  both themes without needing a paired foreground per person.
- **"X is typing" is broadcast, not presence**: it is a pulse, not a state,
  so nothing is left behind if a tab dies. Pings are throttled to one per
  1.5s to keep a 4s flag alive, keyed by thread so typing in one
  conversation does not show in another, and ignored from anyone outside
  your circle.
- **Messages are one table for both kinds of thread**
  (`circle_messages_migration`): a NULL `recipient_id` is the group message,
  a set one is a direct message. The audience is the app's existing
  `shared_circle()` rather than a new membership concept that could drift
  from link groups. Note the deliberate asymmetry: a group message is
  readable by the SENDER'S circle, so what you send reaches the people you
  share with. The client keeps the same idea in one string --
  `CIRCLE_THREAD` or a user id -- and that string is also the key of
  `circle_message_reads`, so unread counts need no second notion of a
  thread. Delivery is `postgres_changes`, which applies the table's own
  SELECT policy per subscriber: nothing about who may read what lives in
  the client.

### Native date inputs, and the "ensure" that returned null

Three traps met in one round of chat work, each of which produced a control
that looked fine and did nothing.

- **An `input[type=date]` never matches `:focus`.** Focus lands on one of its
  own shadow sub-fields, so the host matches `:focus-within` instead --
  measured, `document.activeElement` IS the input while `matches(':focus')` is
  false. Worse, Chrome will not *style* the host off `:focus-within` either,
  though `.matches()` reports true. And `blur` on the host does not reliably
  fire when focus leaves it. **Drive a date field's open/closed state from a
  class toggled on `focusin`/`focusout`** -- the bubbling pair -- never from
  `:focus`, `:focus-within` or `blur`.
- **A programmatic `.focus()` fires no focus event while the pane is not
  focused**, though `activeElement` still updates. So a focus-driven style
  cannot be tested with `el.focus()` in the harness; drive a real click with
  the `computer` tool, which gives the pane input focus. Synthetic typing still
  will not reach a date control's sub-fields, so native typing there cannot be
  verified in the harness at all.
- **An `ensureX()` must return the existing X.** `ensureTypingChannel` read
  `if(typingChannel || ...) return null;`, so every call after the first bailed
  and typing was never broadcast. **Test the SEND path, not only the receive
  path** -- driving the receive side by hand from a second client is exactly
  how this survived a test.

### Repainting off an async state change

Paint a control that reflects a view from the **render function**, not from the
click handler, whenever the handler awaits before setting the view.
`loadCircleFiles` sets `circleChatView` only once its query returns, so a
`paintFilesToggle()` at the press caught the view it was leaving.

### Animating something that is display:none

`.hidden{display:none!important}` cuts a transition off on its first frame. To
animate a panel open: remove `hidden`, read a layout value (`void
el.offsetWidth`) so the transition starts from the closed state, then add the
`.open` class. To close: remove `.open` and only add `hidden` on a timer past
the transition. Anything asking "is it open" must then read `.open`, not
`.hidden`, or it reports open all through the closing animation.

### The sticky header, and three ways it can be quietly wrong

The header and the tab row are one wrapper (`#topBar`) pinned at the top, so
the tabs stay reachable down a long list. Three things had to be measured
rather than assumed.

- **A last child's bottom margin collapses OUT of its parent.** The tab row
  carried `margin-bottom:22px`, so the sticky wrapper measured 22px shorter
  than it looked and content scrolled over that strip. The gap belongs to the
  wrapper as `padding-bottom`, with the child's margin zeroed.
- **A hidden element measures as pinned.** `#appScreen` is hidden until
  sign-in, so anything initialising against it reads a 0x0 box -- and
  `rect.top <= top` is trivially true at zero, which latched the condensed
  state on and left it that way until the first scroll. The test needs a
  `rect.height > 0` guard, and the reveal path has to re-evaluate rather than
  trusting a ResizeObserver to fire.
- **Compare against the element's own resting `top`**, not a literal 0. Body
  padding-top carries `env(safe-area-inset-top)`, so where the bar comes to
  rest differs between a browser tab and an installed phone app.

**`env(safe-area-inset-top)` belongs in the sticky OFFSET, not only in the
body's padding.** `top:0` is the top of the VIEWPORT, and with
`viewport-fit=cover` that is behind the notch and the status bar -- so on the
installed app the bar pinned up out of sight (real-user report: "it's fixed
way too high, it completely goes out") while a browser tab, where env() is 0,
looked perfect. The offset is a calc carrying the inset, a `::before` paints
the strip the bar now sits below (the page still runs through it), and
`--topbar-h` is read back off the RESOLVED `top` rather than adding the pieces
up again, since only the browser can resolve an env().

**Stuck, the header is ONE row**: mark and title left, controls hard right
(real-user request). `flex-direction` cannot be transitioned, so the change of
layout snaps while the sizes still ease. Two things it needs that are easy to
miss: the tagline needs zero WIDTH as well as zero height, or collapsed flat
it is still a flex item claiming the width of its own text on the row; and
the room is genuinely tight, so it was measured -- at 375 the title wants
137px and the controls were leaving it 136, one pixel and an ellipsis for it.
A 3px gap, a pixel off each button and a 12px glyph buy it back. Below about
340 it truncates and should: there is no size the whole title fits at once
the controls have what they need. Phone 184 to **89px (11% of the screen)**,
desktop 175 to 95.

**A screenshot of a condensing bar in this pane is a frame PARTWAY through the
transition**, since transitions only advance when it paints -- the title read
as ellipsised in three consecutive screenshots and was not. Kill transitions
before judging a settled state. And `scrollWidth` under-reports a truncated
flex item (it came back equal to `clientWidth` on text that was visibly cut),
so neither the picture nor that property is trustworthy alone.

**It can be turned off** in Account settings, and is ON by default -- absence
of the key means pinned, so nobody opts in to it. A display preference, so it
lives where the theme and the language do: localStorage, per device, not a
profile column. Off, the bar is `position:static` and `--topbar-h` goes to 0,
since nothing is covering the top of the page for a scrollIntoView to clear;
the condensed class is dropped with it, or a bar switched off while scrolled
stays shrunk with nothing left to un-shrink it.

**It CONDENSES when stuck, and that is not decoration.** Measured first: the
full bar is 184px of a 375x812 phone, 23% of the screen given to chrome for
good. Stuck, the tagline collapses and the title and mark shrink, taking it to
128px (16%); the tabs keep their size, since they are the point. Desktop 175 to
124.

### Two more harness traps, both of which look like app bugs

- **This preview pane dispatches NO scroll events.** `scrollTo()` moves the
  page -- `getBoundingClientRect()` proves it -- and a probe listener on
  `window` counts zero. A scroll-driven class will look completely dead; drive
  it by dispatching `new Event('scroll')` and check the geometry, which is
  layout and therefore honest.
- **It composites `position:sticky` at a stale offset while hidden**, so a
  screenshot can draw a pinned bar most of a screen away from where
  `getBoundingClientRect().top` says it is. Trust the rect. For the same
  reason a transitioned property reads as its START value: `body`'s background
  reported light while the theme was dark, because that transition is frozen.
  Compare the TOKEN (`--paper`) instead of the transitioning property.

## The calendar downloads as a picture, and the crop is LAYOUT (6 Sep)

A Download button in the view-toggle row, offered in all three views. It opens
a dialog that lists everything in range with a tick beside it, all ticked, so
the reader takes things OUT rather than building a selection up (real-user
request). PNG by default, PDF beside it.

**What is excluded is held out of the PICTURE, not out of the calendar.**
`calExportExclude` is a Set of event ids consulted by the two grid renderers,
filled for the length of the capture and emptied in a `finally`. So the
dialog says nothing about the calendar itself, and a failed export cannot
leave the reader's own calendar missing events.

- **The hook goes in exactly TWO renderers**, `renderMonthGrid` and
  `renderCalGrid`. A blind edit finds three -- `renderMonthAgenda` gathers
  events the same way and is deliberately left alone, since the agenda panel
  is hidden during a capture anyway and filtering it would be a second place
  to keep in step for nothing.
- **The controls are hidden with `visibility:hidden`, not `display:none`.**
  `body.cal-exporting` takes out the view toggle, the Download button, the
  month arrows, the jump-date button, the agenda panel and the week's
  more-above/more-below markers. Visibility rather than display so nothing
  reflows: the grid has to be captured at the size it is on screen.

**The week and day views are cropped by LAYOUT, never by cutting the canvas.**
Those views scroll inside their own box, so a bitmap crop would have to know
where the header ends and how tall an hour is in device pixels. Instead the
scroll box is given an explicit height of `(to - from) * HOUR_PX` and the body
inside it a negative top margin of `-from * HOUR_PX`, so the browser lays out
exactly the hours that are wanted and html2canvas photographs it. Both are
restored to `''` in a `finally`. Measured: day 10:00-22:00 comes out
2480x1450 and week 0:00-22:00 2480x2330, which is 44px an hour at scale 2 in
both -- the two agree because neither is guessing.

**The PDF is hand-built, and `CompressionStream('deflate')` is why it is
short.** That stream emits zlib, which is exactly PDF's own `/FlateDecode`, so
the canvas's RGB bytes go in with no encoder: catalog, pages, page, image
XObject and content stream, then an xref table of real byte offsets. A JPEG
`/DCTDecode` path stands in where the stream is unavailable. Verified by
checking every xref offset lands on its object, that the deflate stream starts
`78 9c` and ends on its declared length, and then by opening it in Chrome's own
PDF viewer -- a hand-built file that parses is not the same as one that draws.

**html2canvas is lazily fetched from jsDelivr** on the first export, in the
same way the app's four other CDN scripts are loaded. Nothing is downloaded
for a reader who never presses Download.

### Three ways this went wrong that were mine, not the app's

- **"html2canvas ignores `visibility:hidden`" was a bad test.** The pixel
  probe sampled `--paper` off the card's rounded CORNER as its reference,
  where the card's own ground is `--paper-dim`, so everything differed from
  everything. Comparing the same region captured WITH and WITHOUT the class
  settled it in one go: both control areas collapse to a single uniform
  `234,234,236`. **Compare a region against itself under the two conditions;
  never against a colour you reasoned your way to.**
- **A 0x0 capture was the test setup.** `#calendarCalendarSection` still
  carried `hidden`, so the target had no size. Check the thing being
  photographed is actually on screen before believing the capture is broken.
- **The range label was lopsided and only reading it caught it**: "Sep 1 --
  Wed, Sep 30, 2026", a weekday on one end of a month and not the other. A
  weekday earns its place on a single day (day view) and is noise across a
  range, so the two ends match now and only the later one carries the year.

## A sticky bar that CONDENSES must not change the document's height (6 Sep)

Reported as scrolling slowly near the top making the page jump back up over and
over, "like it cancels my scroll". Measured off the recording rather than
argued about: phase-correlating consecutive frames, the page alternated by
**69px on EVERY frame at 30fps** for as long as a slow scroll sat in the band.
A one-frame-period oscillation is a feedback loop, not a stutter.

**The bar is sticky, it condenses by ~60px, and it sits in NORMAL FLOW.** So
the shrink pulled the whole document up with it (scrollHeight 2215 to 2155,
measured), Chrome's **scroll anchoring** then corrected the scroll to hold the
visible content still, that put the bar back under its own threshold, it
un-condensed, everything moved again. Round and round at frame rate.

**The fix is that nothing below the bar may move.** `#topBarSpacer`, a sibling
straight after it, grows by exactly what the bar loses, so the flow height is
constant and anchoring has nothing to correct.

- **Written in the SAME frame as the class.** One frame of shift is enough for
  anchoring to fire, so `syncTopBarSpacer()` is called synchronously inside the
  same block that toggles `.stuck`, not from an effect or the next frame.
- **A ResizeObserver tracks the 0.18s ease**, so the sum holds all the way
  through rather than only at the two ends.
- **The full height is refreshed off the live box whenever the bar is NOT
  condensed**, rather than measured once. Measured once at reveal it read 358
  against a settled 298, which left 60px of blank paper at the top of the page
  for good. Measuring at init does not work either: the app screen is hidden
  until sign-in, so the bar is a 0x0 box until then, which is why both reveal
  paths (`onAuthed` and the guest one) re-measure.
- **Hysteresis is not the answer here and cannot be.** Once pinned, a sticky
  element's `rect.top` is clamped to its own offset, so a release test written
  against that rect can never fire. Removing the layout shift is what breaks
  the loop.

Verified across the threshold a pixel at a time: a visible card holds ONE
document position, the document height holds one value, the scroll never
self-adjusts on any sample, and the stuck state reads `0000011111111` -- it
crosses once and stays.

## The export is picked ON the calendar, and the list is the other way (6 Sep)

The first pass put the tick list in the dialog, and that was a misreading:
"i wanted to be able to tick them off WITHIN the calendar". So both exist now,
with a switch between them, and **the calendar is the default**.

- **The excluded event FADES rather than vanishing** (`opacity: 0.28`, real-user
  request: "they fade out (not fully)"). It has to still be there and still be
  clickable, or there is no way to change your mind about it.
- **One dialog in two presentations, not two dialogs.** In calendar mode the
  overlay goes `background: transparent; pointer-events: none` and docks its
  box to the bottom; the box takes pointer events back. So the calendar
  underneath stays live and there is no backdrop to accidentally close on.
- **The exclusion set is the single source of truth.** The list's checkboxes
  and the calendar's own chips both WRITE into it and are only ever a view of
  it. It used to be read back off the checkboxes at export time, which cannot
  work once there is a second way to pick.
- **The click is captured on the way DOWN.** A chip already has its own click
  listener that opens the event, so the picker has to pre-empt it rather than
  follow it: a capture-phase listener on the document with `stopPropagation`.
  That also covers the bell and the pencil inside a chip for free.
- **The render hook gates on `cal-exporting`, not on the set.** An excluded
  event is dropped from the picture only while the picture is being taken;
  every other time it renders and is merely faded.
- **`redrawCalGrid` repaints the fade.** A redraw builds fresh chips, and the
  month can be paged and the view switched while the picker is open.
- **Exclusions survive the switch** (the same question asked another way) and
  survive a FAILED export (so Download can simply be pressed again). Closing is
  what clears them, and the success path closes.
- **`#calExportFormat` needs its own font-size.** It reuses `.cal-view-toggle`,
  whose phone rule is `clamp(7px,2vw,12px)` for a row of five sharing 375px --
  which resolved to **7.5px** here and rendered PNG and PDF as good as blank.
  Two buttons in a roomy dialog do not want that row's clamp.

Verified end to end: at capture the grid holds 3 chips of 5 with two ticked off
on the calendar, the PNG is produced, and afterwards the modal is closed, the
set is empty, both body classes are gone and all 5 chips are back unfaded. The
mode persists across a reload and falls back to the calendar with no key set.

## The spacer that fixed the jump then LOCKED the scroll (7 Sep)

The condensing-header spacer went in on 6 Sep and the report came back as the
page refusing to scroll at slow speeds. Measured off the recording: the content
advanced 4 to 8px a frame and was yanked back 58 every dozen frames, for a net
of **two pixels across 161 frames**. Not a stutter, a treadmill.

**The cause was the spacer's own unstick branch.** The class comes off first
and the bar's height follows it through a 0.18s ease, so at that instant the
bar is still condensed -- and zeroing the spacer there dropped "bar + spacer"
from 298 to 89 in ONE frame. A 209px collapse, corrected by the browser moving
the scroll, which put the bar back over its threshold and condensed it again.
The same branch also read the full height off a bar that was still easing back,
latching the CONDENSED height as the reference the whole compensation is
computed from.

**So the spacer is always the difference, with no branch on the class.** The
sum is the full height at every instant in both directions, and a bar really at
full height gives zero on its own. Three things make that hold:

- **The condense is ATOMIC.** Every property that changes the bar's HEIGHT
  lands in the same layout pass as the spacer, because a frame of disagreement
  is a frame the browser will correct the scroll for. That is not just the
  bar's own padding: the header's controls carry `transition: all` and BOTH
  their padding and their icon sizes change on condense, so the override covers
  the header's whole subtree. Scoped to `header` deliberately -- `#tabNav` is a
  SIBLING of it, so the sliding tab pill keeps its own width transition.
  Verified by enumerating computed `transition-property` over the bar and every
  descendant: zero layout properties left, slider still `transform, width,
  opacity`. Note the specificity trap: `#topBar .sub` (1-1-0) beats
  `#topBar header *` (1-0-1), so `.sub` has to be named.
- **The full height is refreshed on EVERY scroll while the bar is at rest**,
  not only when the state changes. Taken once at reveal it read 358 against a
  settled 298, so the first condense was computed against a stale number and
  moved the page by the difference. Reading it live is only safe BECAUSE the
  height is atomic: with no transition there is no halfway state.
- **Nothing inside the bar may be the scroll anchor** (`overflow-anchor: none`).
  The tabs live in it and move up by the whole condense, so the browser holding
  THEM still means yanking the page by exactly that.

**The lesson that cost two rounds: killing transitions to measure hides the
bug.** The 6 Sep verification suppressed them to read settled values, so it
tested the two end states and never the 180ms between them -- which is where
the fault was, and where this pane cannot help either, since it freezes
transitions. Where a fix depends on two things changing together, check the
INVARIANT (their sum) rather than the endpoints, and walk the threshold in both
directions: going back UP is what was broken, and only the down path had been
tried.

## The syllabus field was three rows in a row of two (7 Sep)

Reported as the syllabus sitting on a line of its own with an oversized upload
button. Measured: every `.field` in that form is **57 to 60px** and the
syllabus one was **109** -- label, then the button, then the short-link row,
stacked. `.log-form` aligns to `flex-end`, so the extra 50px stuck UP out of
the row and read as its own line. It was never on a separate line; it was too
tall for the one it was on.

The button and the short link share one row now, which puts the field at 58 and
the whole form on two lines again.

**And the button was not dimensionally big, it was visually heavy**: 34px tall
where the inputs are 40, but a solid black block at weight 600 in a row of
quiet outlined fields. It is `height: 40px` and weight 500 now, so it matches
what it sits beside. Used by four forms (the two on Jobs and the resume upload
as well), all checked after.

The file input's own JS finds its label as the PREVIOUS SIBLING, so that pair
has to stay adjacent through any rewrap.

**Corrected the same day: there is no button at all now.** The field's own
LABEL is the control (real-user request: "maybe we can just make syllabus
clickable"), and it turned out it always had been -- every one of these labels
already carried the `for`, so clicking the word "Syllabus" had opened the
picker all along. It simply never looked pressable, so a second element was
added to say so. It wears the field label's own type with a paperclip and a
dotted underline instead.

- **All seven pickers, not just the reported one** ("and other choose file
  places"): the add-course syllabus, both job files, the public resume upload,
  and the three inside edit-panel TEMPLATE STRINGS, which are the ones a grep
  for markup misses.
- **Two shapes, one class.** A `for=` label sits before its input; a template's
  label WRAPS it. `syncFileChosenName` already handled both (closest, then
  previous sibling), which is why the merge needed no JS change.
- **Where a field had no label of its own** -- the public resume upload -- the
  trigger keeps the words "Choose file". Everywhere else the duplicate plain
  label was deleted, since the point is one element doing one job.
- Removing the three button ids meant removing their `STATIC_MAP` entries too,
  or `applyLanguage` writes into nothing.

## The condensing header is GONE, and that is the fix (7 Sep)

Reported three times, the last as "it STILL locks me if I slow scroll. Because
of the fixed bar... Bro", and the round before that made it worse. So the
feature causing it is out rather than compensated for again.

**A sticky element sits in NORMAL FLOW, so a bar that shrinks when it pins
shortens the document under the reader's hand.** The browser corrects the
scroll to hold the content still, that carries the bar back over its own
threshold, and it un-shrinks. Measured off a recording: the page advanced 4 to
8px a frame and was yanked back 58 every dozen frames, for a net of **two
pixels across 161 frames**.

Three rounds went into compensating for that height change with a spacer -- one
that tracked the ease, then one that never zeroed, then atomic heights and
`overflow-anchor` -- and not one held. The bar keeps ONE height now. It still
pins and still wears its shadow; it simply never resizes, so there is nothing
for the browser to correct. Verified by construction rather than by argument:
stuck and unstuck give the same bar height, the same document height and the
same document position for a visible card, and a walk across the threshold in
both directions sees one value of each and zero scroll drift.

**The honest reason it took three rounds is that none of the fixes were ever
reproduced.** This preview pane will not deliver a real wheel gesture -- it
refuses scroll actions outright while hidden, because it does not paint -- and
`window.scrollTo` does not behave like a wheel, so every one of those fixes
shipped on reasoning alone and each looked fine against the wrong test. Two
rules out of it:

- **Nothing that changes the sticky bar's height on scroll goes back in unless
  it can be driven with a real wheel and watched.** Reasoning is not enough for
  this class of bug; the failure only exists in the interaction.
- **When a fix cannot be reproduced, prefer the construction that removes the
  mechanism over the one that compensates for it.** Each spacer version was a
  cleverer compensation, and cleverness is exactly what could not be checked.

**Getting the one-line condensed header back means taking the bar OUT of flow**
-- `position: fixed` with a constant-height spacer -- where its height cannot
touch the document at all. That is a restructure (the bar sits inside `.wrap`,
so a fixed one needs the max-width and body padding replicated, and the resting
offset written per scroll), not a tweak, and it should not be attempted without
a way to test a real scroll.

## The condensed header is back, because the bar left the document (7 Sep)

"I want the non-full size AND scrolling behaving. You can do it." The entry
above ends by describing this restructure as the way to get the condense back;
this is that work, so its last paragraph is now history rather than a plan.

**A `position: fixed` bar's height cannot reach the document, so it may
condense as freely as it likes.** That is the whole change, and it is why this
one is checkable where the three spacer versions were not: they compensated for
a height change the reader could still be scrolling through, and being one
frame late was invisible until it locked. Here there is no height change in the
document to be late about.

- **`#topBar` is `position: fixed`, full-bleed, and `#topBarSpacer` holds its
  RESTING height for good** -- written once per measure, never on a scroll. The
  page below sits at the same offset condensed or not.
- **`top` is a `max()` of the pinned offset and the resting one**, and JS writes
  only `--topbar-rest` (the resting document offset less the scroll). The pinned
  branch carries an `env(safe-area-inset-top)`, which only the browser can
  resolve, so it never enters the arithmetic -- it is read back once by pushing
  the resting branch to `-99999px` and asking for the computed `top`.
- **A scroll costs one custom property and nothing else.** No layout read, no
  class write, and the stuck test is arithmetic against numbers measured off the
  scroll path (`scrollY >= restTop - pinTop`), so the bar's own height can never
  feed back into the decision that changes the bar's height.
- **The bar sits UNDER the guest banner, whose height is read rather than
  assumed** -- it is sticky at the top and comes first in the document, and it
  wraps to two lines on a phone (31px desktop, 47px at 375).
- **The ResizeObserver watches `.topbar-inner` and the banner, never `#topBar`.**
  Observing the bar means condensing it calls the thing that measures it.

**The column is reproduced with padding on the BAR and `max-width` on the
inner, not both on the inner.** Both-on-the-inner is right until the max-width
actually binds: past 1440px the page's column and the bar's are centred as
different-sized boxes and the bar's content sits 20px in from everything else.
Measured with the max-width forced to bind: content runs 340..940 for both.

### What was measured, and what still cannot be

The pane still refuses a real wheel, so the rule from the entry above stands.
What made this testable anyway is that scroll anchoring corrects a document
whose geometry moved, and that can be checked without a wheel:

- **Toggling `.stuck` by hand**: document height 724 both ways, a visible card
  at the same document offset both ways, spacer unchanged, bar 175 -> 95.
- **A 50-step crawl at 3px a step straight through the threshold** (the exact
  rate and band that used to lock): every step advanced exactly 3px, **zero
  scroll corrections**, the document height one value throughout, and the bar's
  top matched `max(pinTop, restTop - scrollY)` to the pixel on every step.
- Both at 1280 and at 375, and with the preference off (`body.topbar-loose`),
  where the bar goes back to `position: static`, drops `.stuck`, and the spacer
  and `--topbar-h` collapse to 0.

## The whole pill is the button, and the pinned bar breathes (7 Sep)

Three off one screenshot of the header.

**The language pill answers a click anywhere on it now.** The native `<select>`
sat INLINE beside the globe, so only its own text box was a target: the globe,
the padding and the chevron were dead pixels on something that plainly reads as
one button. It is laid over the whole pill at `opacity: 0` instead, and the
words and the chevron are drawn by us underneath -- which is exactly the trick
the narrow-width rule already used, and the same one the name pill uses for its
colour input. It stays a real select, because that is what opens the phone's own
language wheel; what changed is only what is DRAWN. Verified by asking
`elementFromPoint` at all four corners, the centre and over the globe: the
select takes all six.

- **The overlay is unconditional now**, so the 1024px rule is down to hiding the
  label and the chevron, which is all "globe-only" ever meant.
- The font-size clamps moved off the select and onto the label with it -- the
  select is invisible, so its own size stopped deciding the pill's width.

**The controls animate.** They had a hover FILL and nothing else: no ease onto
it, and nothing at all under the finger, so a press read as a page that had not
noticed. 150ms on background, border, colour and shadow, and a **squeeze** on
`:active` (0.94, 60ms) -- a press wants to land at once, and a fill that only
deepens says what the hover already said.

- **Only duration and timing are set on the controls.** Inside `#topBar` the
  transition-PROPERTY list belongs to the condense rule (`#topBar header *`,
  which outranks a class selector), and its list already covers every property
  here. Nothing animates padding or width, which is what the condense snaps.
- **The name pill is hovered and pressed through its colour input, which is its
  SIBLING**, so `#whoName:hover` never fires and the rule has to go through
  `#whoNameWrap`. The language pill's select is a CHILD, so that one is fine.
- `prefers-reduced-motion` keeps the fill and drops the movement.

**And the pinned bar sits 12px off the top.** Condensed, the bar's own top edge
IS the top of the screen (or the underside of the guest banner), and with no
padding the title was hard against the browser's chrome. 12px is the gap the
condensed header already keeps below itself before the tabs, so the row is
centred in its own bar rather than pushed against one edge.

The condense is 68px now rather than 60, so the out-of-flow invariant was
re-measured rather than assumed: 50 steps of 3px through the threshold, **zero
scroll corrections**, one document height throughout, and the bar's top exact on
`max(pinTop, restTop - scrollY)` at every step -- with the guest banner up
(pinTop 31) and without it (pinTop 0). The row is still one height and one row
at 1280 and at 375, and nothing overflows.

## The header comes alive, and the title turns into people (8 Sep)

### Two more colours that were saying the wrong thing

- **"Remind me" was green.** The bell toggle is one control in two states and
  both wore the link green, so the crossed-out bell was the only thing telling
  them apart (real-user report: "remind me is green here"). `.linkbtn.act-on`
  is `--on`, `.linkbtn.act-off` is `--ink-soft`. Measured: on `rgb(79,117,99)`,
  off `rgb(107,109,114)`.
- **The underline ran the width of the button**, so on an icon+text linkbtn it
  crossed the bell and the space after it. A decoration cannot be cancelled on
  a descendant -- that is a spec rule, not an oversight -- so the only way to
  stop it short is to move it off the button onto the words: `.lb-text`, and
  `.linkbtn:has(.lb-text){text-decoration:none}`. A plain text linkbtn is
  untouched.

### A mark is a control too

The delete glyphs got the grow, "smartly" as asked: **1.2 rather than 1.08**
(at 11-15px a 1.08 is invisible), **from their own centre** (a mark sits at the
end of a row, where a left-origin grow walks it out of its column), and they
**land on `--danger` as they go** -- several sit at `--ink-soft` at rest so a
dense list is not a wall of red, and the colour is what a control with no
label has instead of a word to read. `.tap-mark` for anything new.

### The language menu opens below

macOS draws a native `<select>` menu centred ON the control, with the current
option over the button, and no CSS can move it (real-user report: "the
languages cover the button. The drop down should be below"). Nothing can be
done about that except not to use one, so a POINTER gets our own menu at
`top:calc(100% + 6px)` -- the same shape `.cal-seg-picker` already uses. **A
TOUCH device keeps the native select**: its picker is a sheet at the bottom of
the screen, never over the control. Asked as `pointer: coarse`, the same
question the 16px form-control rule asks, not a width guess. Measured: pill
bottom 143, menu top 145.

### Six marks that move

Globe spins, gear turns, bell rings with two waves leaving it, the circle
walks, the name jiggles, and the theme icon rotates in as it is swapped.

- **Every one animates the ICON, never the button.** The button already owns a
  transform (the hover grow and press squeeze from 7 Sep), and an animation and
  a transition sharing one element's transform fight over it -- the animation
  wins for as long as it runs and the button visibly stops answering the press.
  Two elements, no argument. The name is the exception and so its keyframes
  carry the grow themselves, with the shared rule explicitly turned off there.
- **The globe turns about its own vertical axis** (`perspective` + `rotateY`)
  and goes edge-on halfway round. Rotating a flat circle says nothing; that
  half-turn is the only part of it that reads as a sphere rather than a wheel.
- **The bell swings from 50% 15%.** A bell hangs at the top, and pivoting about
  the middle reads as a wobble rather than a ring.
- **The theme swap plays on the ARRIVING icon**, one-shot, and only once
  `themeIconAnimates` is true -- the same function restores the theme at
  startup, and an app that spins its own icon on every load reads as a glitch
  rather than as a response to a press.

### Every letter of the title becomes a person

Hold over "Productivity" and its twelve letters turn into twelve people at
work; hold over "Tracker" and its seven turn into seven people tracking
something. Drawn in the app's own icon language -- a 24 box, stroke, no fill --
so they are the same colourless outline marks as every other icon and take the
title's ink in both themes.

- **A figure is a head, a body, legs and ONE prop.** At the size a letter gives
  it (about 18px) anything more is a smudge, so the prop is what has to read
  and the body is the same five strokes every time. `FIG_BODY` is shared.
- **The letter keeps the width of its CHARACTER** and the figure is absolutely
  positioned inside it, so a whole word can turn into people without the title
  reflowing or the header changing height.
- **The word opens up by 0.18em on hover**, because a person is wider than the
  letter it replaces. Small on purpose. **They still overlap**: twelve figures
  cannot fit in twelve letter-widths unless each is as narrow as a letter, and
  at 9px a person is unreadable. The crowd is the trade, and it is the knob to
  turn if it is wrong.
- **Staggered off each letter's own index** (28ms), so the change reads left to
  right as one movement rather than every letter flipping at once.

### The animation switches are SPLIT

Three, not one master (real-user request: "split to different animation choices
to turn off"): Header icons, Title letters, Interface motion. Each is its own
localStorage key, absent means ON, and each toggles one body class its own CSS
block watches -- nothing else in the sheet has to know they exist. Verified
that turning the title off leaves the header alone. `prefers-reduced-motion`
still turns everything off regardless.

## Settings are six headings, and green means ON (8 Sep)

Four asks off one screenshot, two of them explicitly systemic.

### Settings fold into sections

It was one flat scroll of fifteen unrelated blocks, so finding anything meant
reading all of it (real-user request: "consolidate settings a bit better, so
there's a better overview"). Six groups now, all folded shut: Profile,
Appearance and layout, Notifications and messaging, Privacy, Account and
security, Delete account. **The closed list IS the overview** -- the whole of
settings fits one short card, and nothing is more than one press deep.

- **Every block is the same markup with the same ids, only moved.** The
  regroup was done by cutting each block out of the file verbatim and
  reassembling, with a byte count either side to prove nothing was dropped
  (9,261 in, 9,243 accounted, the slack being whitespace between blocks). None
  of the JS that fills these knows it happened; all 11 spot-checked ids still
  resolve exactly once.
- **The caret is drawn from `aria-expanded`**, not written by JS, so the arrow
  cannot drift out of step with the fold and the state is announced for free.
- **`syncSettingsSections()` hides a section whose every row is hidden**, asked
  of the markup rather than of a list of ids. A guest has no notifications, no
  privacy row and no account to delete, so a guest sees two headings and not
  four empty ones -- and anything gated in future takes its section with it.

### Messaging can be turned off

`MESSAGING_KEY`, same shape as the sticky bar beside it: localStorage, per
device, absent means ON. It gates `updateChatDockVisibility` (the dock) **and
the unread count on the circle button**, which lives on a button the dock does
not own and would otherwise go on asking to be read. Measured with the other
two gates stood up so the pref was the only variable: dock visible on, gone
off, back on.

### One grow, for every control that is a WORD

"For things where you have to click the word for it to work, it should grow
like some of the things we have in settings. Syllabus, for example, currently
does not. Systemic." The grow existed only on `.cal-seg`. It is one rule now,
over `.cal-seg`, file-picker labels, `.linkbtn`, the reminder trigger, and a
`.tap-word` utility for anything new -- 25 controls on the guest screen alone.

- **It is a TRANSFORM, not font-size.** Growing type reflows, which is why the
  recap pills had an exception carved out of the old rule for reading as
  "jittery"; that exception is deleted, because a scale moves nothing around
  it. It is also the same squeeze-on-press the header controls got on 7 Sep, so
  the app has one motion vocabulary rather than two.
- **The vocabulary is a WORD grows, a ROW or PILL lights.** Anything with its
  own border or fill already says where its edges are.
- **`:not(:has(.cal-seg-picker))`**, because an open picker is a CHILD of the
  word and scaling the word would scale the menu hanging off it.
- **And Syllabus still would not have grown**, because `.hidden-file-input` is
  `position:absolute` with no offsets: its 1px box sits at its static position,
  right on the label that drives it and later in the DOM, so it took the
  pointer there. Found by hovering the word and watching the hover land on the
  INPUT. `pointer-events:none` -- it is only ever opened through the label.
  Verified after: hovering "Syllabus" gives `matrix(1.08, 0, 0, 1.08, 0, 0)`.

### Green means ON

"Reminders on is good as green, but when they're not on, why are they green?"
Third meaning in the series `--danger` (removes) and `--edit` (edits):

| | |
|---|---|
| `--on` / `--on-soft` | a state that IS on, set, active, selected |
| `--ink` / `--ink-soft` | everything else, INCLUDING the affordance that would turn something on |

**An invitation is not a state.** The reminder chips and their "Add reminder"
trigger both wore the same green, so green said nothing; the chips keep it
(a set reminder is on) and the trigger is plain ink. Both moved out of a
template literal into real rules, which is what lets the doctrine be stated
once rather than per call site.

- Swept the rest: day pills, recap toggles, the active lecture, read receipts,
  status badges, 2FA status, save/fail messages, the moderator list, money, the
  selected tab. **The presence dot was a THIRD green** (`#3aa675`, close enough
  to look like a mistake beside the real one and far enough to be one).
- **Hover is emphasis, not a state.** Three headers turned green under the
  pointer, which now reads as "this one is on" -- and on a lecture list the row
  next to it really is, in the same colour. They are `--ink-hover` now.
- **The green keeps a second, older job, deliberately**: the app's accent, on
  links, today markers, stat numbers, progress fills, chart bars. Those are
  never on/off. The test is whether the thing can be ON; that is why both names
  exist, and why `--celadon-4` is still named directly in ~45 places.
- **Dark needed its own value.** The light green is 4.31:1 on a card; the same
  value on `#18191B` is 3.3:1, under the floor. Measured after: **light 4.75
  on paper / 4.31 on card, dark 7.58 / 6.68.**

## The globe is a sphere, the title is one name, and the ring holds hands (8 Sep)

Four corrections to the round above, all on the same person's word, plus two
things that were still missing.

### A spinning circle is a wheel; a sphere needs meridians

"When I said spinning globe, it should basically have turned into a sort of 3D
globe that is spinning." The `rotateY` half-turn from the round above spins the
whole mark, which is a disc turning edge-on and back -- correct as a rotation
and nothing like a globe.

**The sphere is drawn instead: an outline, an equator, two latitude ellipses
and THREE meridians, and only the meridians move.** A meridian at angle theta
projects to an ellipse whose width is `cos(theta)`, so the turn is one keyframe
list of scaleX from 1 through 0 to -1 in eight stops, and three copies of it a
third of a turn apart (`--m`, `animation-delay: --m * -0.8667s`). The outline
and the latitudes never move, because on a real globe they do not: that is
exactly what says "this is a sphere turning" rather than "this drawing is
rotating".

- **At REST it is the flat globe the header has always had** -- one meridian at
  `scaleX(0.42)`, no latitudes. The sphere is what it turns INTO, so the row is
  unchanged until somebody holds over it.
- `transform-box:view-box` with `transform-origin` in USER units (12px 12px) is
  what lets an SVG child be transformed about the drawing's own centre.

### The title is one name, and the people ARE the letters

Two corrections in one. **The trigger is the whole title** (`#appTitleHome:hover`,
not `.title-word:hover`), with `--i` counted straight across all nineteen
letters, so the sweep runs once left to right rather than a word at a time
("the animation should be the whole 'productivity tracker' not separately").

And the figures are no longer people doing an activity: **each one stands in
the shape of the letter it replaces**, so the name still reads as a name
("formed in the shapes of the letters (smartly), so you can still read it").
`LETTER_FIGURES` is **14 unique glyphs** for the 19 letters -- P r o d u c t i
v y T a k e -- each a head, a body and whatever strokes the letter needs, on a
`4 2 16 21` viewBox.

- **Legibility was CHECKED rather than assumed**, by rendering all nineteen at
  74px and again at 22px on a throwaway page and reading them back. That is the
  whole point of the change, so it is the one thing that had to be looked at.
- **The word barely opens up now** (0.06em, was 0.18em). A letter-shaped person
  is a letter's width, so the crowding the old figures needed room for is gone.

### The sun turns under clouds and somebody fishes off the moon

The theme toggle was the only mark in the row with no hover of its own. So:
the sun's RAYS turn (9s) while the disc holds still -- a rotating circle is a
circle -- with two clouds drifting across it half a beat apart; and on the
moon a little angler fades in and his line swings out and back (`cast-line`,
about `13.8px 6.2px`, which is the rod tip).

- The angler and the clouds are `opacity: 0` at rest, so the resting icon is
  still the plain sun and moon the row has always had.
- `themeIconHtml(isDark)` builds both, so the swap and the hover cannot drift
  apart.

### Three people, and the arms decide whether it reads

"The people should get a body/legs, a 3rd person should come out, and they
should hold each other's hands in a circle." The first attempt did all of that
and still read as a **network diagram**: big heads (r 1.9) at three triangle
corners with the joining lines running head to head.

Fixed by measurement, not by argument -- three candidate geometries rendered
side by side at 200, 60, 30 and 15px and looked at:

| | what it reads as |
|---|---|
| heads r1.9, arms head to head | three blobs on a triangle |
| **heads r1.3, arms shoulder to shoulder, bowed outward** | **three people in a ring** |
| figures radial, heads outward, tangential arms | a pinwheel |

The middle one ships. The rule that came out of it: **an arm must leave the
SHOULDER and clear the head**, and a head that is a fifth of the icon cannot be
cleared by anything, so the head has to shrink before the arms can be right.
The third person and the two arms that reach them still fade in a beat late
(0.16s), so somebody visibly joins.

### Four settings headings, not six, and the email wears your colour

- **Profile, Privacy and Account and security are ONE section**, called
  **"Account and Security"** and first ("I think Profile can fit Privacy and
  Account and security too"). It holds the display name, the leaderboard
  opt-out, the email change, the password reset and 2FA -- which is one
  question ("who am I and who can get in") asked five ways. Four headings now:
  Account and Security, Appearance and layout, Notifications and messaging,
  Delete account. `syncSettingsSections()` still hides a heading whose whole
  body is hidden, which is why a guest sees two.
- **The email is `myColor`**, beside the name rather than in `--ink` ("the
  email should be your default color"). Written at all three places the name's
  colour is written -- sign-in, guest, and `applyMyColor` -- so the two can
  never disagree. Measured: both `rgb(136,52,178)` on the guest colour.
- **The two animation hints were rewritten**, in all three languages: the title
  one still described the old per-word morph, which no longer exists.

### The tab slider stopped flying past the tab

`cubic-bezier(.34,1.56,.64,1)` overshoots by **9.8% of the distance
travelled**, and that share is the problem: a one-tab hop overshoots 15px and
a jump across the whole row overshoots about 60, so the slider visibly leaves
the tab it is landing on (real-user report: "it goes a bit too far out before
bouncing back in"). **1.3, which is 3.0%** -- about 19px on the long jump and 5
on a short one. The overshoot is a property of the curve and can be computed
rather than eyeballed, which is how these two numbers were picked; the
preview pane freezes a transition at its start value, so it cannot be watched
here anyway.

### Found in passing, in its own commit

`renderLeaderboardPage('articleLeaderboard', ..., 'articles', ...)` passed a
`stateKey` `lbState` had no entry for (it held study, reading, jobs, certs), so
the articles leaderboard threw `Cannot read properties of undefined (reading
'expanded')` on every render and never drew. Pre-existing and unrelated to the
rest of this round, so it is a commit of its own. **The console buffer here is
CUMULATIVE across navigations**, which cost a diagnosis: the same errors came
back after the fix and after a reload, and the way to tell a live error from a
stale one is a NEW TAB (or an `unhandledrejection` listener installed by hand),
not another read of the log.

The rule the bug is worth remembering for: **a lookup table keyed by a string
passed in from five call sites needs the call sites checked against the table**,
which is three lines of node and is now part of the verification pass.

## The marks fill their pills, and the little people get something to do (8 Sep, later)

### Nineteen letters, nineteen jobs

"The people who turn into letters should be productive in various ways. And
for the tracker part, should be tracking various things." So each figure keeps
the letterform pose from the round above and gains ONE prop: a laptop, a pen
and the line it just wrote, a bulb, an open book, a list, a broom, a case, a
hammer, a parcel, a mug, a cog and a paint roller across Productivity; a
magnifying glass, binoculars, a map pin, a stopwatch, a rising line, a ticked
box and a calendar across Tracker.

- **Keyed by POSITION, not by letter.** r, c and t each appear in both words,
  and what a letter is doing is decided by the word it is in, so `LETTER_PROPS`
  is a nineteen-entry array read by the same index that drives the stagger.
- **Each prop goes where that letterform leaves the box EMPTY**, so it never
  crosses a stroke the reading depends on -- the P's laptop sits right of its
  bowl, the t's case hangs off the end of its arm, the k's chart runs off its
  raised hand.
- **And it is thinner AND dimmer than the glyph** (1.05 against 1.7, at 0.7).
  At full weight the nineteen props formed a second row of marks above the
  letters and the name stopped reading, which is the one thing this drawing
  exists to protect. Checked by looking at the hovered title at 2.4x.

### The pills were mostly air

15px marks in a 31px pill (real-user report, with the row screenshotted).
**19px, with 2px less padding on every side**, so the pill does not move: 15+20
and 19+16 are both 35 of ink and padding, 15+14 and 19+10 both 29. Applied to
the two control ROWS (`.who`, `.topbar-controls`) rather than to `.icon-btn`,
which is a text pill in three dozen other places where 8px would be tight, and
the three responsive padding rules each lost their 2px so the row still
collapses the way it did. Measured after: button 37x31, mark 19x19.

### A cloud that does not hide anything is a cloud-shaped hole

The sun's two clouds were outlines, so they drifted THROUGH the disc rather
than in front of it (real-user request: "fill them, so they cover parts of the
sun"). The fill is the button's own hovered background, mixed rather than
guessed: `.icon-btn:hover` REPLACES the background with a translucent grey, so
what is really behind the mark is 16% of that grey over the page's paper, and
`color-mix(in srgb, var(--paper) 84%, rgb(127 127 127))` is exactly that in
both themes. They only ever show on hover, so that is the only state the fill
has to match. The moon's cloud uses the same rule.

### The moon is a BOWL, and the angler has a whole beat

"The guy who fishes on the moon should fly in from a sky, sit down on the
bottom edge of the moon (btw you need to make the moon more oblong for this),
does some fishing in a pond ... then he jumps in, the water disappears, and the
cloud flies back in with him on."

- **Same crescent, turned and stretched about its own centre** (`rotate(-40)
  scale(.8 1.1)`), which turns the notch into a bowl with a lip to sit on. Its
  stroke is 2.15 rather than 2 to pay for the scale: `vector-effect:
  non-scaling-stroke` was tried first and is wrong here, because it pins the
  stroke to SCREEN pixels and this icon is drawn at more than one size.
- **The seat and the waterline are MEASURED off the crescent, not guessed.**
  Sampling the inner arc in a browser puts the bowl's floor at (13.8, 10.7) and
  its left lip at (10.1, 9.8), so the water lies at y 9.6 and he stands at
  x 10.4 -- far enough right that his feet clear the moon's own arm, which they
  did not at first.
- **The cloud and the guy are keyed at the SAME percentages**, and his track is
  simply the cloud's plus (1.8, -2.6), which is where somebody standing on it
  is. That is what keeps them in register while he is aboard without nesting
  one inside the other, and it means the loop is seamless: he arrives from the
  left, is dropped, fishes, jumps in, and the cloud comes back from the right
  and carries him out the left again, which is where the loop began.
- **He is teleported while invisible.** Between jumping in and being picked up
  he is at opacity 0, and that is the window the keyframes use to move him from
  the pond to off-screen right, so nothing is ever seen to jump.
- **The rod's line pivots on `transform-box: fill-box`**, not a viewBox
  coordinate: the whole figure is translated all over the icon, and a fixed
  point in the viewBox stops being the rod tip the moment he moves.
- **The water waves.** Two straight rules under a swinging line read as a
  bench, which is exactly how the first pass looked.

### The linked circle MORPHS

"The linked circle looks stupid. I wanted them to properly morph, not just show
a different image animated." It was two drawings cross-faded, and that can
never read as a morph: nothing on screen travels between the poses.

It is ONE drawing at two sets of coordinates now -- two people standing, who
shrink and walk into a ring while a third grows out of the middle and takes
their hands. The morph is CSS on the geometry itself: `cx`/`cy`/`r` on a head
and `d` on a torso, its legs and its arms.

- **Every part has to keep its COMMAND LIST across both poses** or the browser
  stops interpolating and cuts. So a torso is always M+V, legs are always
  M+l+M+l, and an arm is always M+Q -- which is why the idle figures have one
  curved arm each rather than the straight ones that would be natural.
- **Both poses are written in the stylesheet**, not left on the attribute for
  one end, so there is nothing to interpolate FROM that the sheet cannot see.
- **The ring only starts turning once the morph has landed** (a 0.4s animation
  delay), or it rotates while it is still forming.
- Verified in the browser at 6x: the idle mark reads as two people, the hover
  lands on three in a ring, and the rotation follows.

## The title measures itself, and the moon gets the reference picture (8 Sep, fourth pass)

Four corrections to the round above, all on the same person's word.

### Nineteen little people were the wrong answer, twice

First they were people doing activities, then people posed as the letters, then
people posed as the letters DOING activities -- and the verdict on the third
was "this looks hella stupid. Maybe come up with another smart idea that are
not these small men. Do whatever you find the most clever."

**So the title does the one thing the app is named for: it TRACKS.** Held over,
the letters tick to the "on" green one at a time from the left, a meter under
the words fills at exactly the same rate, and a check lands when it reaches the
end. `LETTER_FIGURES`, `LETTER_PROPS` and `figSvg` are all gone -- about 60
lines of hand-drawn glyphs replaced by two transitions and a stagger.

- **The lesson worth keeping**: whatever the title does on hover, the NAME has
  to stay the name. Drawings standing in for letters cost legibility however
  carefully they are posed; colour and a rule underneath cost none of it. Three
  rounds went into trying to buy the first one back.
- **19 letters x 34ms = 0.65s**, which is the meter's own duration and the
  check's delay. Those three numbers have to move together or the bar and the
  letters disagree about when the title is finished.
- **The meter and the check are both ABSOLUTE**, inside a `.tl-track` that
  wraps only the words. The h1 also holds the logo, so a meter spanning the h1
  would span that too -- and a check laid out inline would reflow the header
  every time the pointer crossed the title.

### The moon is the reference picture

"That's not what I meant by an elongated moon. I mean like the one in this
picture", with the stock illustration: a thin crescent, its bulge on the right,
a figure on the bottom tip fishing into a ripple below.

**Drawn rather than transformed** (the previous pass rotated and scaled the
stock crescent, which needed a `vector-effect` that pins the stroke to SCREEN
pixels and so stops being 2 units the moment the icon is drawn at any other
size): an r8.6 circle at (12.4,12) with an r7.9 bite at (9.8,11.4) taken out of
it. **The two horns are the intersections of those circles, solved rather than
eyeballed** -- (10.76,3.56) and (7.22,18.87) -- and that bottom one is what he
sits on.

- **He flies in on a cloud, hops to the tip, fishes, jumps in, and the cloud
  comes back for him.** The cloud and the guy are keyed at the same
  percentages, his track being the cloud's plus (1.8,-2.6), which is where
  somebody standing on it is; between jumping in and being collected he is at
  opacity 0, and that window is what the keyframes use to move him off-screen
  right without anything being seen to jump.
- **The ripples are rings, and that needed a THINNER stroke than the group's.**
  At rx1.5/ry0.45 a 1.2 stroke is wider than the ring it is drawing, so both
  came out as solid blobs; they are rx2.1/3.6 at stroke 0.8 now, scaled about
  the point the line enters, which is where a ring spreads from.
- **Two stars twinkle** in the half of the box the crescent leaves empty.

### The pills, again, and the bell's rings were off centre

- **23px, not 19** (real-user report: "I still dont think you fully filled out
  the pills"). Padding drops to 3px/6px so the pill is the same 37x31 it has
  always been; the three responsive rules each lost 4px rather than 2.
- **The bell's rings were positioned as a 16px box and DRAWN as 19** -- a 1.5px
  border on each side that the -8px margin never accounted for, so they sat
  down-right of the bell (real-user report, with a screenshot). They are
  centred by the box model now (`inset:0;margin:auto`), which cannot be out
  however the border or the padding change.
- **The clouds are a shade PAST the backdrop colour** (72 rather than 84).
  Filled to the exact colour behind them they occlude perfectly well and still
  read as the sun being erased rather than as a cloud in front of it, which is
  what "the clouds are not filled" was about.

### The circle is TWO people, and the busts come back

"I hate the men you did for the circle. Maybe just make it the two men who hold
hands creating a circle. And make something similar to the original icon back."

So at rest it is the two busts the button has always worn -- a big head with
wide shoulders and a smaller one behind it, which is the stock users mark -- and
held over, those same elements become two people standing, with the circle
being the one their joined arms make between them. Three figures in a ring are
gone.

- **The command lists are what the poses have to share**, and they now are
  M+C+C for a body, M+C for a leg and M+Q for an arm. That is why the busts'
  shoulders are written as two cubics rather than as the arc the stock icon
  uses: an arc cannot interpolate into a torso.
- **The legs and the arms START at nothing**, inside the bust, and are what
  grows when the two of them stand up -- a bust has neither.
- **The size difference between the two heads is load-bearing.** At 3.4 and 2.6
  they read as a face: two eyes over a wide mouth. At 3.6 and 2.4, offset
  further right, they read as one person in front of another.

## A cloud is a silhouette, and something runs the title (8 Sep, fifth pass)

### "They should simply be all white"

Two passes filled the sun's clouds with the colour BEHIND the icon, reasoning
that a cloud should hide the sun without becoming a blob. Both read as the sun
being rubbed out rather than as a cloud in front of it, because **a shape the
colour of its own background is not a shape**. `fill: currentColor` -- white in
the dark theme, near-black in the light one -- makes it a silhouette, which is
what a cloud crossing a bright sun actually is. The moon's cloud with it.

### The rays glint one at a time

The eight rays were ONE path, so the only thing they could do together was
pulse. They are eight paths now, ordered round the circle from the top and
carrying their own index, so a 0.17s stagger sends the light travelling round
the sun instead of the whole mark breathing. **Scaled about the sun's own
centre**, which lengthens each ray and pushes its tip out; a plain opacity fade
is a lamp on a dimmer, not a glint.

### Something runs the length of the title and draws the check

The check was `0.62em` and read as a footnote beside a 22px title. It is
`0.92em` now, and it is DRAWN rather than faded in: a dot hops along above the
letters while they tick over, and the stroke follows it in as it lands.

- **The runner travels on `left`, not on a transform.** The distance it has to
  cover is the TRACK's width, and a transform percentage is a share of the
  element's own size. One element, only while hovered.
- **The hop is on an inner element.** The run owns `left` and the bounce owns
  `transform`, and one element cannot animate one property from two places.
- **The check draws with `stroke-dasharray`/`dashoffset`** (24 units, which is
  that path's own length), starting at 0.64s -- the same 0.65s the letters and
  the meter take, so all three finish together. Those numbers move as a set.

## The theme lands in ONE frame, and the pair stay where they are (8 Sep, sixth pass)

### A theme swap is not one repaint, it is however many transitions the page has

Reported with a recording: "since the two parts of the site are kinda split,
the dark/light mode doesnt apply simultaneously and makes it look funky."

The theme is a swap of custom properties, and every surface that paints one
changes at whatever rate ITS OWN transition says. So the page came apart while
it switched:

| | |
|---|---|
| `body` | eased its background over **0.2s** |
| `#topBar` | fixed, paints its own `--paper`, **no transition** -- snapped |
| the header's pills | eased over their own **0.15s** hover transition |

**Giving the top bar a matching transition fixes the two surfaces somebody
happened to notice and nothing else.** There are dozens more -- every card,
input, chip and sheet that paints a token -- and each would have to be found
and kept in step for good. So **nothing transitions while the swap happens**:
`body.theme-swapping` sets `transition:none !important` on every element and
both pseudo-elements, the tokens change under it, and it comes off two frames
later. Measured during a real toggle: body, `#topBar` and the theme button all
report `transition-property: none`, and 0.7s later the button is back to its
own six.

- **A layout property is read between adding the class and toggling `dark`.**
  Without that forced reflow both changes land in one style recalculation and
  the browser is free to transition anyway.
- **Animations are untouched**, which is what leaves the icon's own spin alone.
- **A timer backs up the two `requestAnimationFrame`s.** A backgrounded tab
  gets no frames at all, and a page that came back with every transition still
  switched off would be a strange thing to leave behind.
- `body`'s own `transition:background,color` is gone. The only thing that ever
  changed that background was the theme, so easing it bought nothing and was
  half the fault.

### Filled is right for the sun and wrong for the moon

The moon's cloud is carrying somebody, and solid it swallowed him whole
(real-user correction: "only for sun ones, they should be full white"). It is
an outline again -- and **he rides ON it rather than in it**: his offset from
the cloud went to (2.2, -4.8), which puts his feet on the cloud's own top edge
rather than 1.1 units down inside its shape.

### The pair hold hands where they already stand

"Why cant you just animate these where the guy in the back comes to the right
and the guy in the front is on the left and then they join together in a
circle? so you dont have to shift the entire icon image."

Each figure now stays in the HALF of the icon its own bust already occupied --
the front one steps left, the one behind comes out to the right -- so the mark
never picks itself up and moves. **And it does not turn.** Three people in a
ring read as a ring seen from above, so rotating them was the ring turning;
two holding a circle between them are seen from the front, and rotating that
is two people falling over.

## The busts MOVE, the strapline goes, and the sub bar steps aside (8 Sep, seventh pass)

### The cheapest morph is the one that redraws nothing (superseded, see the eighth pass)

Asked twice, and the second time verbatim: "why cant you just animate these
where the guy in the back comes to the right and the guy in the front is on
the left and then they join together in a circle? so you dont have to shift the
entire icon image."

Two passes had interpolated the shapes themselves -- busts into stick figures
with legs -- which is precisely the "shift the entire icon image" being
objected to. **Each bust is a GROUP carrying one transform now.** Held over,
the front one steps left and the one behind comes out right, both shrinking a
little as they part, and a circle grows between them where their hands meet.
Nothing is redrawn, so nothing can come out looking like a different mark.

- **They shrink because two busts at full size have no room between them** to
  hold anything: the front one spans over half the box on its own.
- `transform-box: fill-box` with `transform-origin: center`, so each scales
  about its own bounding box and stays in its own half.

### "Study · Reading · Jobs" is gone

Superfluous (real-user request). The element, its i18n key in all three tables,
its STATIC_MAP entry and the four CSS rules that only ever styled it all went
with it -- including the condense rule that collapsed it when the bar pinned,
which now has nothing to collapse. `.header-row2` is `justify-content:flex-end`
rather than `space-between`: with the strapline gone there is no left-hand item
to push the controls right.

### The fly-out no longer lands on the sub bar

Hovering a top-level tab drops its sub-tabs in a row that covered the real
sub-tab bar underneath. **The bar steps DOWN out of the way instead**, by
transform, so nothing else on the page moves -- the gap under it is already
exactly deep enough (real-user request: "we dont have to move anything else
... there is EXACTLY enough space for the sub bars to move down").

- **The bar is found by MEASUREMENT, not by a class.** Every panel names its
  own sub-bar differently, and what matters is not what it is called but
  whether it is a short row sitting immediately below the nav -- which is
  exactly the thing the fly-out would land on. `subBarUnderNav` takes the
  visible panel's first child and keeps it only if it is under 60px tall and
  within 40px of the nav's bottom.
- **How far is computed, not measured.** At that moment the fly-out is still
  parked at `translateY(-100%)`, so its own rect is a whole height above where
  it lands; the target is `nav.top + itsTop + 4 + itsHeight`.
- **Hovering the pushed bar keeps the fly-out open.** Stepping from one to the
  other would otherwise close it and shift the row back under the pointer,
  which is the constant-shifting the request was about.

## The pair end up the same person, and the ring is two half circles (8 Sep, eighth pass)

Third pass on the circle icon, and the one that finally says what the mark is
for. The seventh pass's "each bust is a GROUP carrying one transform" is
SUPERSEDED: a single transform per bust can only ever scale a head and its
shoulders together, and the two figures start at different sizes and have to
finish at the same one.

Asked for exactly (real-user request): "the guy in the back head's would grow a
bit to be the same size as the guy at the front, move a bit more to the right
(and guy in the front a bit more to the left) so you can see his other arm, and
the arms (that are already there) lock together in a circle (now that they're
on either side)."

### Every part moves on its own, and none of it is redrawn

Six elements now -- two heads, two pairs of shoulders, two arms -- each
animating its OWN geometry: `cx`/`cy`/`r` on the circles and `d` on the paths.
Still a real morph rather than a cross-fade, because every path keeps its
command list across both poses, which is the only thing that lets `d`
interpolate at all.

- **The head behind grows 2.4 to 3.6, which is the head in front unchanged.**
  That is what "the same size as the guy at the front" means, so the front head
  is the one number in the whole pose that does not move.
- **His single shoulder UNFURLS into a pair, and that is the other arm.** The
  stock mark draws the figure behind as a half arc, `M` + `C` + `C`, because
  the one in front hides his left side; the full arc the figure in front wears
  is `M` + `C` + `C` as well. So one interpolates straight into the other: the
  neck point slides down and left to become the far hand, the mid-arm point
  rises to become the neck, and the near hand steps right. Nothing new is
  drawn; the arm that was hidden is the arm that unrolls.

### The shoulders narrow, the heads do not

Both figures end up 0.70 of the stock shoulder width. That is forced
arithmetic, not taste: at full width two busts leave about three units between
them, and a 2-unit stroke needs more than three units of ring before the ring
has any hole in it at all. Narrowing the shoulders buys 5.6 units of gap while
leaving both heads at their full 3.6, so what shrinks is the half of each
figure nobody is looking at.

### A quadratic cannot draw a circle, and the first version proved it

The arms were two quadratics bowed opposite ways. A quadratic's end tangent
points at its control point, which sits on the midpoint, so the two curves meet
at a hard corner and the enclosed shape is a pointed lens -- at this stroke
weight it filled in completely and read as a small diamond.

They are **cubics whose control points sit `4r/3` beyond each end**, which is
the standard half-circle approximation: it passes through the apex exactly,
leaves both ends vertical, and is under 0.03r off a true circle anywhere along
it. So the two arms really do close as a circle.

- **At rest each arm is COLLAPSED onto the ring's own centre** (`M12.4 16.4C12.4
  16.4 12.4 16.4 12.4 16.4`) rather than lying flat somewhere else, so the ring
  opens out of a point between them instead of sliding in from a place nobody's
  hands are. It runs 0.13s behind the pair, so they have stepped apart before it
  closes.

### What the tuning actually costs, since it was measured rather than guessed

Rendered side by side at 230px and at 23px through eight passes. Two dead ends
worth not repeating: letting the ring OVERLAP the shoulders (so the figures can
stay big) puts both shoulder arcs through the ring's interior and leaves a blob
rather than a hole; and shrinking the figures far enough to clear a big ring
takes the heads back down to about 2.4, which is the size the one behind
started at -- so the grow that was asked for stops happening at all.

## The grid is as tall as the day is, and the fly-out only moves what it lands on (8 Sep, ninth pass)

### A day column drawn midnight to midnight is mostly empty rows

Real-user request: "dont need to include a bunch of times of day where there is
nothing." A week of classes runs 9 to half past 5, and the grid was drawing all
twenty-four hours around it, so most of the picture was ruled paper and the one
morning with anything in it had to be scrolled to.

`calGridHourRange()` takes the range off the events being DRAWN -- the
`eventsByDate` the same render pass just built -- so it is one hour either side
of what is actually there. The user's own week goes from **nineteen hour rows
to eleven**.

- **The EXPORT crops itself for free now**, and its own `calExportHourRange`
  plus the `marginTop` shift under a clipped wrapper are gone. The export
  redraws the grid with its excluded events left out before capturing, so by
  the time the picture is taken the grid already holds only the hours those
  events occupy. Two pieces of arithmetic for one question is how they drift.
- **An untimed event legitimately pulls the range back to midnight**, because
  that is where an untimed bar is pinned. It is not a bug to fix; it is where
  the thing is being shown.
- **Never shorter than eight rows.** A single one-hour event would otherwise
  leave a three-row grid, which reads as a broken calendar rather than as a
  quiet day. It grows downward first, so a short morning keeps its events near
  the top of the picture rather than floating in the middle of it.
- Checked against the shipped source over seven shapes: the reported week comes
  out 8 to 19, one short event 13 to 21, a late-only day 16 to 24, an early-only
  day 0 to 8. Then driven through the real `renderWeekGrid`: eleven labels from
  8 AM to 6 PM, a 484px column, and three bars at exactly 44, 176 and 308.

### The row snapped back up because its own rect had already moved

The seventh pass's push measured how far the sub-tab row still had to go as
`flyoutBottom - bar.getBoundingClientRect().top`. That rect is the box AFTER
the transform, so the second fly-out asked a row that was already held down and
got an answer of nothing -- which clamped to zero and let it spring back
underneath the new fly-out (real-user report: "when moving from one to another,
it goes back up, so it still covers it").

**The offset is read off the USED transform** (`getComputedStyle(...).transform`
through a `DOMMatrixReadOnly`), not off the value last asked for. Those are
different numbers: the row is mid-glide whenever one fly-out follows another,
so neither its rect nor the target it is travelling towards says where it is.
Measured: Home and Study now both answer **19px, every time, settled or in
flight**, where Study used to answer 38.

### And it only moves a row the fly-out really lands ON

"We only need to push it down if it is actually overlapping something. So the
right tabs usually don't need to do it, because they don't touch anything."

The row is a full-width container with three pills at its left end, so its own
rect claims the whole width and reported an overlap with a fly-out hanging
under a tab at the far right. **The test is against what the row DRAWS** -- the
union of its own buttons -- so it is 20 to 290 rather than 20 to 1260, and a
fly-out at 542 to 738 misses it. Measured live: Home and Study push, Yonsei,
Reading and Jobs push nothing.

- **The landing box comes from `offsetTop`/`offsetLeft`, not from the nav's
  rect.** Those are measured from the offset parent's padding edge and are
  untouched by a transform, so they answer the same whether the fly-out is
  parked above the nav, sliding in, or already sitting there. Reconstructing it
  from `navRect.top` was out by the nav's own border, and being short by a
  couple of pixels is exactly what left the row still half covered.
- The clearance is a named `FLYOUT_GAP` (8px) rather than a 6 buried in the
  arithmetic.

## The morph was never running, and the shadow was what cut over (8 Sep, tenth pass)

### `#topBar header *` had been cancelling every geometry transition

"Also the circle icon is not a morphing animation where the head grows and
moves aside. You simply just made a new image."

Exactly right, and it was not the drawing: **nothing was interpolating.** The
condense rule further down the stylesheet pins the property list for
everything inside the bar --

    #topBar, #topBar header, #topBar header *, #topBar h1{
      transition-property:opacity,background-color,color,border-color,box-shadow,transform;}

-- so that a `flex-direction` swap cannot be half-eased. It carries an ID, so
it outranks a plain class, and it knows nothing about SVG geometry: `cx`, `cy`,
`r` and `d` were struck off the icon's own list and every one of them SNAPPED.
Two poses with no frames between them is a second drawing, which is precisely
what was reported.

**Measured rather than reasoned about**, and the measurement is the thing worth
keeping: `getComputedStyle(el).transitionProperty` on the head read
`opacity, background-color, color, border-color, box-shadow, transform` while
`transitionDuration` read `0.42s, 0.42s, 0.42s, 0.42s` -- four durations
against six properties, so the durations were mine and the properties were not.
`el.getAnimations()` on a real hover returned an empty list for the heads and
the bodies, and `["opacity"]` for the arms: the one property the blanket list
happens to contain.

- **A standalone probe circle transitioned `cx` and `r` perfectly**, which is
  what ruled the browser out and pointed at the cascade.
- The fix is an id the rule does not otherwise need: `#topBar .fr-head` is
  (1,1,0) against the blanket's (1,0,1), so it wins on class count. Nothing
  else moves. `getAnimations()` now answers `[cx, cy, r]` on the head behind,
  `[d]` on its shoulders and `[d, opacity]` on the arms.
- **`CSS.supports("transition-property","r")` is worthless here** -- that
  property takes a `<custom-ident>`, so it answers true for any word at all.
  Ask the element what it ended up with instead.

### The clearance had to clear the SHADOW, not the box (half right, see the eleventh pass)

"It still cuts over." The box was clear by eight pixels and the shadow was not:
`.tab-flyout-item` carries `0 4px 12px rgba(0,0,0,0.3)`, which is **sixteen
pixels of grey past the border edge**, so a row eight below it sat inside all
of it.

`flyoutShadowReach()` reads that off the computed `box-shadow` -- offsetY plus
blur plus spread -- rather than repeating it as a number here, so the two
cannot drift when the shadow is retouched. Total clearance is that plus four of
real air: the row now moves **31px** where it moved 19.

- **Capped at the room there actually is**, measured against the first thing
  below that PAINTS rather than against the box containing it: a section's own
  top padding is room the row can move into without touching anything. Under
  the calendar's sub bar that is 33px against the 30 wanted, which is what "there
  is EXACTLY enough space for the sub bars to move down" was describing -- the
  row ends up with its bottom edge on the card below it, and nothing else on
  the page has moved.

### The title had a whole line to itself

"I dont know what the productivity tracker title is doing all the way up
there." The header was a COLUMN because the row under the name used to hold the
strapline as well as the controls; with the strapline gone (seventh pass) the
controls kept a line of their own and the name kept another.

It is one row now -- name at the left, controls at the right, wrapping only
where a phone makes it -- which is what the condensed bar already was, so the
condense no longer swaps direction at all. The h1's own 4px bottom margin went
with it: on one row that only pushed the name off centre.

## "Cuts over" was the row landing on the card, and the budget is six pixels (8 Sep, eleventh pass)

"When i say still cut over, i mean we push down the subtabs over the 'jump to'
for example or other boxes below them in the other tabs."

So it was never the fly-out over the row. It was the row over the CARD, and the
cap that was supposed to stop that was measuring the wrong thing.

### A bare wrapper is room; a card is not

`subBarRoomBelow` walked down to the first element with any HEIGHT, which took
it straight through `#calendarOverviewSection` and the `.card` inside it to the
card's own `<h2>`. So it reported **33px of room where there were 12**, and the
row was moved 31 -- nineteen pixels into the card, which is exactly what was
being seen. The walk stops at the first element that DRAWS A BOX now (a
background, a background image, or a top border), because that is what
"landing on something" means: padding is room, a card is not.

### And the whole budget is six pixels, which no shadow fits in

Worth writing down as arithmetic, because it is what settles every number here
and there is no room left to tune by feel. With `m` the nav's own 22px bottom
margin, `h` the 28px fly-out, `o` its offset below the nav, `s` its shadow's
reach and `g` the air wanted under it, the row has to move `o + h + s + g - m`
and can only move `R`:

    o + s + g  <=  R - h + m  =  12 - 28 + 22  =  **6**

The offset, the shadow and the air share six pixels. The shadow alone was
`0 4px 12px`, which reaches **sixteen** past the border edge -- so it could
never be cleared however far the row moved, and shortening it to `0 2px 5px`
(seven) still could not. **There is no shadow on the fly-out now**; its 1px
border and dimmer fill are what separate it, which is what the sub-tab pills
under it already rely on.

- **And it sits flush under its tab**, `translateY(0)` rather than 4px lower.
  Those four pixels are two thirds of the budget, and flush reads as belonging
  to the tab it hangs from. It also removed a number: the landing rect was
  adding a 4 copied out of the CSS, and `offsetTop` alone is now the answer.

Measured across every tab, with the cap in place: Home pushes **11 against 12
of room**, Study 11 against 16, and Yonsei, Reading and Jobs push nothing at
all because their fly-outs hang beside the pills rather than over them. Air
under the fly-out is 5px everywhere it moves, and the row clears the card by
1px on Home and 5 on Study. Nothing overlaps in either direction.

## The download dialog can be moved, and the picture is only the calendar (8 Sep, twelfth pass)

### It is dragged by its heading

"Let me move this box around." In pick mode the dialog is parked over the very
calendar it is asking you to click, and whether that is in the way depends
entirely on which week is on screen -- so where it sits has to be the reader's
call rather than a dock's.

The heading is the handle, which is the one strip of the box with nothing to
press on it and what every window in every OS uses. Three things make it hold
up:

- **It is an OFFSET applied as a transform, not a position.** Whatever the
  layout decides is home still decides it -- centred as an ordinary dialog,
  docked at the foot of the screen in pick mode -- and the two swap while it
  is open without either knowing this exists.
- **The clamp measures the box with the drag taken OFF.** Reading its rect
  through the transform folds the drag into its own limits, and the box then
  walks off the screen one drag at a time. Verified: dragged hard at the
  top-left it stops at 8,9 and at the bottom-right at 1272 of 1280 and 813 of
  820.
- **Every open starts home.** Moving it is about seeing past it this time, and
  it is also what makes switching presentations safe: the mode switch reopens,
  and an offset that was inside the window centred can be outside it docked.

`pointercancel` as well as `pointerup`, or a touch the browser reclaims as a
scroll leaves the drag running until the next finger lands.

### The picture is the calendar, and nothing else

Three things left out (real-user request, with the crops): **the bell, the
pencil and the repeat mark** on every chip, which are the editor's own controls
and a downloaded week is not something anybody presses; and **the heading and
the Month/Week/Day row**, which were a title and a set of buttons taking two
lines of a picture that is meant to be a calendar.

- **`display` rather than the `visibility` the older rule uses**, and that is
  not only about the space: **html2canvas paints a `visibility: hidden` box
  anyway**, which is why the toggle kept turning up in the download while the
  rule above it said otherwise. The controls that sit AROUND the grid keep
  `visibility`, because taking their space would move the very boxes the
  capture is about to measure.
- **One `!important`, and it is earned**: `#calDownloadBtn` carries its own
  inline `display`, which nothing in a stylesheet can outrank, and it has to
  go rather than be hidden or the row it shares with the toggle keeps its
  height and the picture opens on an empty band.
- **Which view it is rides on the date line now** -- "Week · Sep 13 - Sep 19,
  2026" -- and only in the picture. On screen the Month/Week/Day row two lines
  up already says it, and a second copy beside the dates would be saying it
  twice.

## Online, the green moves into the ring (8 Sep, thirteenth pass)

"Maybe move the green (if online) to that circle in the middle there when
hovering." So it does: the dot slides off the button's corner into the ring
the pair have just closed, fading out as it lands, and the ring takes the
same green on the same clock.

- **The dot FADES rather than shrinking into the hole**, and that was decided
  by rendering it rather than by argument. The ring's hole is **3.4px across**
  at 23px, so a pip that fits inside it reads as nothing at all; 1.9px of
  green stroke reads at 23px and at every size above it. Four candidates were
  drawn side by side at 23, 46 and 180px -- a pip in the hole, a disc covering
  the ring, the ring's own stroke in green, and the last two together -- and
  only the green stroke survives being small.
- **It is placed against the BUTTON's own centre, not in pixels off its
  corner.** The icon is 23px and centred whatever the pill does, so the ring's
  middle is always 4.22px below that centre (4.4 viewBox units at 23/24) and no
  pill size is baked in. Measured after: the dot lands at 18.5, 19.7 in button
  coordinates, which is the ring's centre to the tenth of a pixel.
- **`stroke` had to go in the arms' own transition list.** The bar's blanket
  `transition-property` (see the tenth pass) knows nothing about it either, so
  the colour would have snapped the way the geometry used to.
- Online is read with `:has(#circleOnlineDot:not(.hidden))`, off the same
  element the presence code already toggles, so there is no second copy of
  "somebody is online" to disagree with the first.

**And a cache trap worth knowing.** The rules were on disk and `document.
styleSheets` did not have them: the preview pane had served the page from
cache. Any check that reads back CSS should confirm the rule EXISTS before
concluding it does not apply, and a `?v=` on the reload settles it.

## The condensed row drops the WORDS, not the marks (8 Sep, fourteenth pass)

"The english should just be the globe and the green circle should be smaller
when these symbols shrink. However, these symbols DO NOT NEED TO SHRINK THIS
MUCH."

Measured at 1280 in the pinned bar, which is where this happens: the language
pill was **103px of a 204px row** while every mark beside it had been squeezed
to **12px** in a 16x14 pill. The wrong half was giving way -- the label is the
one thing on that row nobody needs, and it was the only thing keeping its size.

- **The label and the caret go whenever the bar is condensed**, at any width.
  Under 1024px they already did; the condensed bar is one line by definition,
  so it has the same reason at every width. Dropping them buys 78px, which is
  what pays for the marks going back up to **17px** in a 25x21 pill. The row
  comes out at **166px against 204** with everything in it half again as big.
  The invisible select still covers the pill, so tapping the globe opens the
  OS's own picker with the full names.
- Checked at 375 as well, where the condensed row is tightest: brand 162 plus
  controls 166 against 335 of header, and no horizontal overflow.

### One number, so what is sized against the marks follows them

`--who-icon` on `.who` (23px, 17 when condensed) is what the marks read, and
the online dot is derived from it: 8/23 of it wide, its halo 2/23, its resting
inset 4/23 -- so a row that shrinks takes the dot with it instead of leaving an
8px dot on a 14px button. And the ring the dot flies into on hover is
`4.4/24 * --who-icon` below the button's centre, which is the same viewBox
offset the last pass measured, expressed so it holds at any mark size.
Verified in the condensed bar: the dot lands at 12.5, 13.61 against a ring
centre of 12.5, 13.62.

- **A dead rule went with it.** `.who .lang-switch-icon{width:15px}` had been
  outranked by `.who .lang-switch > svg` (a type selector beats it) for long
  enough that the globe was 23px while the rule and its comment both said 15.
  A rule that cannot fire is worse than no rule: it is a wrong answer waiting
  for somebody to trust it.

## The admin block joins the list, and the green lands as the circle (8 Sep, fifteenth pass)

### Two more folds, from the four that already existed

"Make moderator collapsable too, and match the resume part to the rest in
terms of formatting." The resume block had a hand-rolled disclosure of its own
(`resumePublicOpen`, a `.note-group-header`, its own click listener and its own
arrow drawn into `innerHTML`) and the moderator block had no disclosure at all,
just a `.wtc-title`. Both are `.set-group` sections now, so the delegated
handler that already folds the other four folds them too and the hand-rolled
copy is gone.

- **`#moderatorSection` is `display:contents`.** It is a GATE, not a box: left
  as a box its two sections would be a list inside the list and their rules
  would not line up with the four above. Its first section drops its top rule,
  which would otherwise land exactly on the bottom rule of the section above
  and draw as one 2px line.
- **The heading's words come from the table now**, through STATIC_MAP, rather
  than being written into `innerHTML` by the disclosure it no longer has.

### The circle in the middle IS the online dot

"You didnt add the green circle in the middle" ... "i mean, you did, but it
should be the online circle." Two goes at this, and the corrections are the
useful part:

| tried | why it was wrong |
|---|---|
| the dot shrunk into the ring's 3.4px hole | reads as nothing at all at 23px |
| the dot faded out and the RING went green | a green outline is not the online dot |
| **the dot lands at the ring's own outer size** | what the pair are holding IS the light |

7.8/24 of the mark, which is half a pixel wider than the ring's 7.25px outer
diameter, so it covers the arms' stroke rather than leaving a hair of it
showing. Measured settled: 7.47px at 18.50, 19.71 against a ring centre of
18.50, 19.72, opacity 1. The arms still take the green underneath, which is
what stops antialiasing at the disc's edge reading as dark.

- **`width` and `height` had to join the dot's own transition list** for the
  same reason `stroke` did on the arms: the bar's blanket `transition-property`
  does not carry them, so it would have jumped to size.

## The fly-out is swallowed by its tab (8 Sep, sixteenth pass)

"Right now these pop out boxes glide up and disappear when moving your mouse.
But they should animate to collect under the main tab (it swallows them)."

It parked at `translateY(-100%)`, which slides the whole row straight up behind
the nav wherever it happens to be. It carries a `scale(0.22)` in that state
now, about a `transform-origin` written per hover -- **the middle of the tab it
belongs to, in the fly-out's own coordinates**, which is not its own middle: the
row is clamped against the nav's edges, so a fly-out under one of the end tabs
sits well off to one side of it.

Measured through the collapse under Home: 241px wide at left 24, then 122 at
82, and it lands 71 wide centred on **143 against the tab's own 142**.

- **`offsetWidth`, not the rect, for the clamp.** The shrink is on the parked
  state, so a rect measured through it reports a fifth of the real width and
  the clamp then centred every fly-out a hundred pixels left of its tab. Caught
  by the transform-origins coming out at 26px on a 241px row; layout width is
  the one measurement a transform cannot touch.

## The note is written beside the list, and named by clicking its name (8 Sep, seventeenth pass)

### The editor moves to the right of the list when there is room

"So much empty space here. Could just move the note writing section to the
right of this when there is space." The lecture list is a narrow column of
titles and the editor was stacked under it, so on a wide screen the whole page
was one column of text with two thirds of the width empty beside it.

`.notes-split` wraps the two cards and is a plain block until **1100px**, where
it becomes a flex row: the list at `flex:1 1 0` and the editor at
`flex:1.35 1 0`, so the side being typed into gets the larger share. Measured
at 1400px the list is 578 and the editor 764, on one row; at 900px both are
860 and stacked. `min-width:0` on the children, or a long lecture title stops
the list shrinking and the editor never gets its share.

### The lecture is renamed by clicking its name

"Let me rename the lecture by clicking on the name here." Clicking
`#editorLectureTitle` swapped in the whole `buildNoteMetaFieldsHtml` panel,
which is every field the note has when the ask was for one of them.

It replaces the heading with an `<input class="lecture-title-input">` in its
place, in the heading's own face and weight so the line does not jump: Enter or
blur saves, Escape restores. Only for a note the signed-in user owns, and only
one at a time (`span.dataset.editing`).

- **Escape while renaming must NOT close the note.** The input calls
  `stopPropagation`, so the document-level Escape below never sees it.

### Cmd+S saves and Escape closes

One document `keydown` listener routing through the buttons that already exist
(`#saveNoteBtn`, `#closeNoteBtn`) rather than a second copy of what they do, so
the key and the button can never disagree. Gated on `#editorCard` being
visible, and Escape stands down while any `.modal-overlay` is open, since the
dialog on top owns that key.

Verified: with the editor open, meta+S and ctrl+S both reach save and Escape
reaches close; with it hidden, neither fires.
## The fly-out is swallowed from BELOW, and a tick box you can see (8 Sep, eighteenth pass)

### translateY(-100%) is what sent it over the main tabs

"The animation goes above the main tabs instead of below it, so it looks weird
instead of the tab swallowing the pop-up sub tabs."

Parked, the row carried `translateY(-100%) scale(0.22)` -- a whole row-height
UP, which is past the tab and into the nav. So the thing supposedly collecting
into the tab travelled ABOVE it and was swallowed from the wrong side.

**There is no translate at all now.** The origin's y is already 0, which IS the
tab's own bottom edge (the row is positioned flush under it), so a plain
`scale(0.2)` about the tab's centre keeps the row pinned there and shrinks it
into the tab from underneath -- the direction it came out of. The row fades
with it, so the shrunken box does not sit there as a speck.

**The sub bar still pushes down**, which was asked for separately and is
unchanged: it was the pop-out's own travel that read as the sub tabs being
swallowed, not the push (real-user reports, in order: "you made these get
swallowed. Revert that", then "Not the sub tabs here. I was talking about the
pop out sub tabs").

### An unticked box was drawn in the colour behind it

"The tick box is almost impossible to see. You have to outline them."

`--line` is **12% ink in the light theme and 14% in the dark one** -- a
hairline in almost exactly the surface colour, which is right for a divider and
useless for a control. The box is `1.5px solid var(--ink-soft)` now, which is
the token for a mark that has to be read without shouting and is defined per
theme, so one value covers both; hover goes to full ink. Checked, nothing
changes: the mask is the shape there and gives the border away anyway.

### An action that has a symbol is drawn as the symbol

"Change to only use our symbols for all of these type of things (edit, remind
etc). we already do this in course notes. Should be site-wide."

Six `Edit` word-buttons (books, articles, jobs, certificates, events,
expenses) are `ICON.pencil()` now, and the reminder toggle is the bell alone --
`bellOn` against `bellOff` IS the state, so the word beside it said the same
thing twice. The word survives as the `title` and the accessible name, so a
pointer and a screen reader both still get it.

- **`.linkbtn.act-icon` carries no underline**, since an underline under a
  drawing is a line under a drawing, and it takes 3px of padding: the mark is
  14px and a 14px target is not one.
- **The moderator row is deliberately left in words.** Five different word
  actions sit in it (reset password, confirm e-mail, disable 2FA, delete user)
  and a lone pencil among them reads as the odd one out rather than as the
  same thing said shorter.

### The rename was a control that could do nothing and still advertise itself

"I cant edit the title by clicking on it." Driven with a real mouse click
against the real markup, the handler works end to end -- input in place,
focused, text selected -- so what is left is the two ways it can decline:

- **It is somebody else's note.** Renaming belongs to whoever MADE it, which is
  the rule the list's own pencil already follows (`isMine`). The title now only
  wears the dotted underline, the pointer and the tooltip when it can really be
  renamed, so it never offers what it will refuse. `setEditorLectureTitle` is
  the one place that writes the title, so the words and the affordance cannot
  drift.
- **The lookup was keyed on `selectedNotesCourse`.** A note is filed under its
  course id, or its header, or `__none__`, and the realtime handler re-files it
  on every UPDATE -- so a note open while its course or header changes
  underneath it is no longer in the group the editor was opened from, and the
  lookup answers nothing. `openNoteRecord()` falls back to a scan of every
  group and re-points `selectedNotesCourse` at where it really is.

**And it is not on the deployed site until it is pushed.** The rename shipped
in a commit, and this project's rule is that Kristoffer pushes.
## A note can be split into pages (8 Sep, nineteenth pass)

"Add an ability within notes to 'separate into pages,' so you dont have to get
a continuous running note page."

**A page break is an `<hr class="note-page-break"> INSIDE the note's own
HTML**, and that one decision is what makes the rest cheap: saving, the version
history, the realtime delta, the export and the schema all go on seeing exactly
one document. A note with no break in it is byte-for-byte what it always was,
there is no migration, and there is no second table holding pages that could
drift from the note they belong to.

- **It is registered as a Quill BLOCK EMBED**, not left as a bare tag. The
  editor's content is loaded by writing `root.innerHTML` directly, which
  bypasses Quill's parser -- so an unregistered `<hr>` renders and is then
  dropped the first time anything is typed near it and Quill reconciles the
  DOM against its own model. With `blotName`/`tagName`/`className` declared it
  round trips: measured, typing into the paragraph before a break leaves the
  document as `{insert:"AlXXpha\n"}, {insert:{notePageBreak:true}},
  {insert:"Beta\n"}` and the `<hr class="note-page-break">` still in the HTML.

### One page at a time is HIDING the others

Which is the second decision that keeps this small. Nothing is split out of the
document and nothing has to be joined back, so there is no way for a page to be
lost on save: the pages are the runs of top-level blocks between the breaks,
and every block that is not on the page being read takes a `display:none`
class.

- **Re-applied after every text change**, so an edit that makes Quill rebuild a
  block heals the hidden ones on the next keystroke rather than leaving half a
  page on screen.
- **The page follows the CARET while typing**, so inserting a break lands you
  on the page you have just made and deleting one cannot leave you looking at a
  page that is no longer there.
- **The rule itself is hidden too while paging.** It is there to say where one
  page ends when they are all in a row; a dashed line hanging under the only
  page on screen says nothing.
- **The break is filed with the page it ENDS**, so hiding a page takes its own
  bottom rule with it rather than leaving a stray line under the page above.

### The two controls, and why they are where they are

- **Insert is in the TOOLBAR**, beside the other things you put into a
  document. It cannot live in the page bar: that bar only exists once there are
  two pages, and this is the control that makes the first one.
- **The bar says nothing at all on a note with one page.** "Page 1 / 1" over
  every note in the app is a control that has nothing to control.
- **Showing them all again is one press**, remembered per browser -- it is a
  way of reading rather than a fact about the note. Default is one page at a
  time, since that is the whole point of asking for pages.
- Both note editors have it (Yonsei course notes and the Notebook), off one
  pager keyed per editor, so the two cannot end up behaving differently.

**And printing is where a page break earns its name**: `break-after: page`
under `@media print`.

Driven against the real editor rather than reasoned about: three pages show
one paragraph each with prev disabled on the first and next on the last, "Show
all pages" brings back all five blocks including both rules, and the toolbar
button at the end of the document takes it to 4 of 4.
## The tab chews, the name shines, and the Notebook catches up (8 Sep, twentieth pass)

### A thing that swallows something has to move

"I kind of want the main tabs to have an animation where they move (grow and
then shrink again) so it looks like they actually ate the hover pop-out sub
tabs. Same for when they spit them out."

Two keyframes on the tab itself, and **both are timed against the fly-out's own
0.22s travel rather than picked**: the SPIT squeezes first (22%) and releases as
the row comes out of it, and the GULP is delayed 60ms so its bulge peaks at
0.23s -- the moment the row finishes collapsing back in. Squashed on the y more
than the x, because what is going down is going down THROUGH it.

- **Safe on the button itself.** `.tabs button` carries no transform of its own,
  so nothing is being overwritten -- the trap this file already records twice.
  And a transform lays nothing out, so the four `flex:1` tabs beside it do not
  budge.
- **remove, reflow, add.** Hovering the same tab twice plays nothing at all
  otherwise: the class is already on the element, so there is no change for the
  browser to start an animation from.
- **The tab that OWNS the row is remembered** (`tabFlyoutBtn`), because the
  close does not know which tab it came out of. That also makes the good case
  fall out for free: hovering straight from one tab to the next makes the first
  swallow and the second spit, rather than the row silently teleporting.
- **A close with nothing open chews on nothing.** `hideTabFlyout` is called
  defensively from several places and a tab twitching for no reason is worse
  than no animation.

Verified through the real `showTabFlyout`/`hideTabFlyout`, not by adding the
classes by hand: `tab-spit` running with ownership taken, `tab-gulp` running
with ownership cleared, and moving between tabs giving the first `tab-gulp` and
the second `tab-spit`.

**`isMobileDevice()` answers TRUE in the preview pane**, and `showTabFlyout`
returns on it before anything happens -- which is why hovering a tab there
appears to do nothing at all. Stub it to drive this path.

### The name SHINES, it does not move

"I dont want the pill itself to move when hovering over name. Just make the
name shine a bit." It jiggled, and the jiggle carried `scale(1.06)`, so the
whole pill grew and rocked. There is now no transform in those keyframes at
all: a `text-shadow` glow that swells and fades over 0.9s with a small
brightness lift under it.

**The glow is `currentColor`**, which is the reader's own colour -- written
inline per account -- so it lights up in whatever they picked without the rule
having to know what that is. The `transform:none` on hover stays, since the
shared word-grow would otherwise be a second thing moving it.

### The Notebook was a screen behind

"You forgot to add the notes stuff in the other notebook." It was: the two
column split, the inline rename and the two keys all went into the Yonsei
course notes and stopped there.

- **The split is the same `.notes-split`**, with both editor cards named in the
  one rule that gives the editor the larger share.
- **The rename is now ONE function** (`wireInlineTitleRename`), called twice
  with the table and the lookup that differ. The Notebook's title used to open
  the whole meta panel, exactly as the course notes' did before it was changed;
  that panel is still what the list's own pencil opens.
- **The keys are one function too** (`wireEditorKeys`), and it tests
  `offsetParent === null` rather than the hidden class: a note left open in one
  tab keeps its own card unhidden while the whole PANEL around it is
  `display:none`, so both editors would otherwise answer the same Cmd+S.
- Pages were already wired into both editors; measured here, the Notebook's
  toolbar carries the insert and its own bar reads Page 1 / 2 with only the
  first page's blocks visible.
## The fly-out cannot leave the screen, and it follows a tab change (8 Sep, twenty-first pass)

"The sub tabs are still flying out of the screen sometimes?? Doesn't happen
under homes or jobs, but happens under the rest." And: "if I go back to Home or
Korean, while having it hovered, it overlaps with the sub tabs."

**The second one reproduces exactly and has one cause.** A fly-out held open
while the top-level tab CHANGES is now hanging over a different panel's sub
bar -- and nothing pushes that one, because the push went with the panel that
was just hidden. `mouseenter` does not fire again (the pointer never left), so
`showTabFlyout` never runs and the new row is never measured. The push is its
own function now (`applyTabFlyoutPush`) and `switchTopLevelTab` runs it again.

- **Retried for a few frames**, not run once: the panel was unhidden in that
  same tick, so its sub bar can still measure nothing on the next one, and
  `subBarUnderNav` answers null for a row with no height.
- Measured through the real path: sitting on Korean, hovering Home's tab pushes
  Korean's bar 10px; switching to Home with the row still open leaves **Home's**
  bar pushed 10px instead.

**The first one does NOT reproduce**, and that is worth writing down rather
than claiming a fix. Driven through the real `showTabFlyout` at nav widths of
1240, 600, 340 and 260, every fly-out lands inside both the nav and the window
and every collapse origin is inside its own box. So instead of guessing at the
instance, three things make the whole CLASS impossible:

- **The row can no longer be wider than the bar.** `max-width:calc(100% - 8px)`
  with `flex-wrap:wrap`. The clamp could not save it on its own: with a row
  wider than the nav, `navWidth - flyoutWidth - margin` falls under the left
  margin, the `Math.max` wins, and the row is laid against the left edge with
  its tail off the far side. Capped, it takes a second line -- and the push
  arithmetic follows for free, since that measures the box's real bottom.
  Measured: at nav 600 and 340 the row is two lines, at 260 it is three, and at
  none of them does anything overflow.
- **It is clamped against the WINDOW as well as the nav**, which is not the
  same box: the nav is one element on a page that can be padded, centred or
  scrolled sideways, and the only thing that really has to hold is that the row
  is on the screen.
- **The collapse origin is clamped INTO the row.** A clamped fly-out can sit
  entirely to one side of the tab it belongs to, and scaling about a point
  outside itself throws the shrinking row that way rather than collapsing it in
  place -- which is the one mechanism in here that could genuinely fling
  something sideways.

**And the tab's rect is read BEFORE the chomp is played.** The keyframes start
at `scale(1)` so it was honest either way, but a rect read through a running
animation is a rect that depends on when it was read, and every number in that
function is derived from it.
## Parking the sub bar down was tried and REVERTED (8 Sep, twenty-second pass)

Worth keeping as a dead end rather than deleting, because the reasoning for it
was sound and it still lost.

The ask was "you dont need to push them down after the tab is opened when it's
pressed ... you can simply have it as keeping it down state in that case ...
otherwise the sub tabs jiggle up and down", so a press made with the fly-out
already up left that panel's row parked where the fly-out had put it: armed by
the press rather than the hover, cleared by any other switch, and nothing
released it while you stayed on that tab.

**On screen it read as the sub tabs simply sitting too low**, and the movement
that was supposed to be a nuisance turned out to be the part that made the row
look alive: "Now you moved the normal sub tabs too far down and removed the
push", then "they should push. Just like before. Literally the only problem was
the pop-out sub tabs that were overlaying the main tabs ever so slightly."

So the jiggle was never the fault -- the fly-out sitting flush on the tab was,
and that is `FLYOUT_TOP_GAP` in the pass below. The push is back exactly as it
was: level at rest, 12px down while a fly-out is really over it, level again
when it goes, whether or not the tab was pressed on the way.

**The lesson is the one this file keeps re-learning**: a report about a
side-effect ("it jiggles") is not a request to remove the mechanism. Find what
made the mechanism run more often than it should, or in this case what made it
visible at all.

## The fly-out stands off the tab, and the four pixels are found rather than taken (8 Sep, twenty-third pass)

"The pop-out sub tabs cover a bit of the main tabs." Flush is what it was:
`top = btnRect.bottom`, so the row's own top border drew ON the tab's bottom
one and the two read as a single object. `FLYOUT_TOP_GAP = 4`.

**It also has to clear the chomp**, which is the reason 4 rather than 1: at the
gulp's peak the tab is scaled 1.11 on the y, and on a 34px tab that is 1.9px
past its own bottom edge -- so any gap under 2 is eaten by the animation every
time it plays.

### The four pixels come out of the fly-out, not out of the row below

This column has a fixed budget and Kristoffer measured it himself when the push
was built ("there is EXACTLY enough space for the sub bars to move down"), so a
gap added at the top is a gap taken from somewhere else. Written out, with H
the fly-out's height and G the new gap:

    clear      = G + H - 18        what the row must move to be clear
    push       = min(clear, 12)    12 being the room the panel leaves
    air below  = 12 - push
    air above  = push - clear + 4

At H = 28 and G = 4 that is a push of 12 with **2px** above the row and none
below -- the fly-out ends up nearer the row than the 4px `FLYOUT_GAP` asks
for, which is the gap two earlier passes were spent getting right. So the
pixels are taken from the fly-out instead: **the items go to `padding:5px`**,
H = 26, and the whole column comes out at **4.5 / 4 / 0** -- measured, in that
order, tab to fly-out, fly-out to row, row to card.

The zero at the bottom is not a squeeze: it is the row sitting in exactly the
gap the panel gives it, which is what that gap is for. Every other arrangement
of these numbers spends it somewhere less useful.

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

## A hidden sibling is not a floor, and it was throwing the sub bar off the top (9 Sep, twenty-fourth pass)

"The subtabs still fly out of the screen due to the pop-out sub tabs when you
have the Korean tab selected (only that one for some reason)."

Reproduced exactly, and the number names the fault outright. `subBarRoomBelow`
walks to the first element under the row that draws a box and answers with the
distance to it. The element directly under a sub bar is that panel's FIRST
sub-view, and every sub-view but the first is `display:none` -- which reports a
0,0 rect. So the room came out as **-184px**, `Math.min(clear, room)` took the
smaller of 12 and -184, and the push wrote `translateY(-184px)`: the row went
up behind the header and off the screen.

- **It was never about that tab.** Every panel is laid out sub bar, then first
  sub-view, so what really decides it is WHICH sub-view is open -- on the first
  one the sibling is visible and the room is real, on any other it is nothing.
  He was on Notebook, which is why it read as being about Korean.
- **Two guards, because they answer different questions.** A zero-height
  sibling is SKIPPED, since a hidden element is not a floor at all; and the
  answer is floored at 0, because this number is how far the row may be pushed
  DOWN and the one thing it must never express is moving it up into the tabs it
  hangs from.
- Measured on the reported state: room -184 before, **16 after**, push +13,
  which is the row stepping aside exactly as it does on the first sub-view.

### The ✕ was a 51-pixel button, and that was the "huge gap"

"Also noticed the huge gap here" (screenshot: an expense row reading
`Groceries · Paid by Kristoffer · pencil ........ ✕`).

The base rule is `button{padding:10px 20px}` and `.item-del` resets background,
border, colour and font-size and **not padding**. So every bare ✕ in the app
was a **51x35 button with the glyph twenty pixels in from its own left edge**,
and the row's 8px gap was really 28. `padding:0;line-height:1` -- 51x35 to
**11x15**, glyph-to-glyph gap 28 to 8. `.note-del` and `.gram-resource-del` had
the same omission and are fixed with it.

### An icon-only linkbtn is a MARK, not a word

"And the fact that the pen does not expand like the X does."

This file already records the two motion vocabularies: a WORD grows 1.08 from
its left edge, a MARK grows 1.2 from its own centre because at eleven to
fifteen pixels 1.08 is invisible. The pencil is a mark drawn as a `.linkbtn`,
so it was taking the word's rule -- an 8% grow on a fourteen-pixel drawing,
which is nothing. `.linkbtn.act-icon` is in the mark vocabulary now (later in
source order AND more specific than `.linkbtn:hover`, which is what lets it
win), and **the grey hover box went with it**: one row carrying two different
hover affordances side by side is exactly the inconsistency being reported.

**And `.item-meta .linkbtn` was quietly undoing `.linkbtn.act-icon`.** Same
specificity, later in the file, so inside a meta row an icon button had its
padding put back to 0 and its underline turned back on. `:not(.act-icon)`.

### The ↗ is a mark too, so the underline stops at the word

"The diagonal arrow should not be underlined (Link and Syllabus and other
places where we have links like that). Only the word."

The glyph was part of the STRING (`linkOpen:'Link ↗'`), so it sat inside the
link's own decorated run. **A text-decoration cannot be turned off on a
descendant of the element drawing it** -- but it does not propagate into an
atomic inline-level box, so `display:inline-block` is what actually lifts it.
`extLinkLabel(key)` appends `<span class="ext-arrow">`, the twelve strings lost
their trailing " ↗", and the span carries the word space as a margin.

- **`resumeViewLink` had to leave `STATIC_MAP`**, whose loop writes
  `textContent` and so cannot carry a mark that is its own element.
- The arrow is `aria-hidden`: the link's own words are the name.

### Every edit is the pen

"Asked you change all edit buttons to the edit pen icon we use. You haven't."

Three were left as words -- the course list's, the grammar row's, and the
moderator panel's "Edit name". All three are `act-icon` pencils now with the
word surviving as the title and the accessible name. `vertical-align:middle`
went onto `.linkbtn.act-icon` for the grammar one, which sits on a text line
beside two word buttons rather than in a flex row.

## Enter saves the expense (9 Sep, twenty-fifth pass)

"Let me press enter to save."

The expense modal is a `div`, not a `<form>`, so **Enter had no meaning at all**
in it -- and typing an amount and hitting Enter is what anybody does. A keydown
listener on the modal, skipped in the three places the key already means
something:

- **on a button**, where the browser fires that button's own click, and for
  Delete that is emphatically not Save;
- **while the category list is open**, where Enter belongs to whichever option
  is focused;
- **mid-composition** (`e.isComposing`), since an IME's Enter commits the
  Korean or Vietnamese being typed into the description rather than submitting.

**A held Enter repeats, and this writes a row**, so `saveExpenseSubmit` is now
one at a time -- the flag is set AFTER the validation, since a form that failed
validation has started nothing to be in the middle of, and cleared in a
`finally` so an alerted error does not leave it stuck.

Escape closes it too: `expenseModal` was simply missing from `MODAL_CLOSE_BTN`.

Checked by dispatching the real event from each element: fires from the amount,
description, date and paid-by fields (4 of 4, `preventDefault` on each), and
does NOT fire on the Delete button, on the Save button, with the category list
open, mid-composition, or on any other key (5 of 5).

**This pane cannot press a key.** `computer type` inserts the characters (the
field really does fill in) but `computer key` delivers nothing at all -- a
document-level CAPTURE listener counted zero keydowns for both `Return` and a
typed `\n`. So a key path has to be driven by dispatching a `KeyboardEvent` at
the element, which exercises the listener and its bubbling path honestly and is
the only thing available here.

## A day, and one expense on its own, can be left out of the totals (9 Sep, twenty-sixth pass)

"Put a - in the top right hand corner of every day that has expenses in the
expenses tab, so you can exclude those", then "and should also enable you to
exclude specific things that have been added as expenses in a day".

The categories have been parkable since the filter was built; this is the same
idea at the two grains under it. **Three filters, one predicate**: `expIsCounted`
answers for category, date and expense id together, and every figure on the
screen reads through it, so the Total tile, the average, the breakdown's
percentages and the month's day totals cannot disagree about what is being
counted. `expRerenderCounts()` redraws all four from every toggle -- which also
fixes the category toggle, which used to leave the day list stale.

- **Not persisted and not synced**, the same call the categories made: a filter
  that quietly survives a reload is how a total lies to you weeks later. A
  parked DATE is also cleared when the vacation changes, since a date belongs
  to the trip it was parked on.
- **Balances are deliberately untouched by all three.** Deciding not to READ a
  day does not change who paid for it.
- **The breakdown's own totals are built from what the DAY and ROW filters
  leave**, and the category filter is applied after that -- a parked category
  still has to show what parking it is costing, where a parked day should
  simply not be in the picture.
- **What is excluded stays on screen, struck through.** The day keeps its
  number and its total, the expense keeps its name and its amount. The number
  that was taken out of the total is exactly the thing worth still being able
  to read, which is why the day's own exclusion is left OUT of the sum that
  cell prints.
- **The mark is only on a day that has something to exclude.** A control in the
  corner of an empty day would be one that does nothing.
- **It stops propagation**, or excluding a day would also select it: two
  answers to one press, and the cell's own click is the louder of them.
- **`ICON.minus` and `ICON.plus`** rather than glyphs, and the corner button is
  a plain `.linkbtn.act-icon.act-off` with nothing added but a corner to sit in
  -- so it inherits the mark vocabulary, its 1.2 grow and its reduced-motion
  guards for free. Positioned at 3px rather than 2 so that grow still lands
  inside the cell, which clips its overflow.
- **"Count everything again"** appears above the grid only while something is
  parked -- the way back for a day or a row left out in a month you have since
  scrolled past. The categories keep their own reset, which sits with the rows
  it resets.

Driven against a stubbed vacation (four expenses over three days, ₩180,400):
excluding the ₩150,000 day gives **₩30,400 over 2 days**, so the average moves
with the day count rather than only the total; adding the ₩22,000 row gives
₩8,400; putting the day back gives ₩158,400; the reset returns all five figures
to base. The breakdown re-totals to 100% at every step, the labels flip between
"Don't count this day" and "Count this day", clicking the mark leaves the
selected day alone, and a day with no expenses carries no mark.

**₩ reads as a strikethrough in a scaled screenshot.** Its two horizontal bars
smear into one line across the numerals at small sizes, so three stat tiles
looked struck through and were not -- `getComputedStyle().textDecorationLine`
said `none` for all of them and `line-through` for the one that really was.

## A trip can be edited, let go of, and deleted (9 Sep, twenty-seventh pass)

"I am unable to edit or delete these", then "and when there is only 1, I can't
unselect it", then "when you close things on click, it currently closes it on
release click. So when you try to highlight something and go beyond the tab it
closes it".

### The backdrop only closes a dialog the gesture BEGAN on

**A click fires on the nearest common ancestor of where the pointer went DOWN
and where it came back UP.** So selecting text inside a dialog and releasing
past its edge lands a click on the BACKDROP, and the dialog went away taking
the selection with it. Thirteen overlays had the same
`if(e.target === e.currentTarget)` and now share `closeOnBackdrop(overlay,
close)`: `pointerdown` records whether the gesture started on the backdrop, and
the click still has to land there too.

Driven through all four cases: a real backdrop press-and-release still closes;
pressing inside the card and releasing past its edge does not; pressing the
backdrop and releasing INSIDE does not either; and a genuine backdrop click
straight after a drag-out still closes, so the flag is not left stuck.

### Edit and delete were never blocked by the database

The table has had `vacations_update` and `vacations_delete` on
`is_vacation_owner` since the feature was built -- only the UI was missing, so
**no migration was needed**. A pencil rides in each pill, and the form is the
create form doing both jobs, the shape the expense modal already has.

- **Only on a trip you OWN.** Both policies are owner-only, so a pencil on
  somebody else's trip would be a promise the database refuses to keep.
- **The pencil is a SIBLING of the pill** -- a button cannot contain a button
  -- so the two sit in one bordered inline-flex wrapper and read as one object
  rather than as a mark floating between two pills. A pill with no pencil drops
  the room for one (`:not(:has(...))`).
- **`hNewVacation` and `createVacationBtn` left STATIC_MAP**, whose loop would
  put "New vacation" and "Create vacation" back over an edit at the next
  language change. Same reason `expModalTitle` is not in it.
- **A currency the picker does not list comes back as the free-text one**
  rather than silently reverting to USD: "Other" has always accepted a plain
  code, so an edit has to be able to show one.
- **Deleting says what goes with it, and names the trip.** `expenses` and
  `vacation_members` are both `on delete cascade` from the vacation, so the
  whole trip's log goes at that moment, for everyone on it.
- Narrowing the dates leaves an expense outside the new range exactly where it
  was. It still happened, and the month grid already draws an out-of-range day
  faded rather than hiding it.
- Enter saves here too, on the same exceptions as the expense form, and the
  same one-at-a-time guard.

### Pressing the trip you are on lets go of it

With two trips you can always leave one by picking the other; with one there
was no way off it at all, because `switchActiveVacation` returned early on the
id it already held. It toggles now.

**And that needed a third sentence in the empty state.** "Create a vacation
above to start logging expenses" is plainly wrong advice when you have two and
simply have not picked one -- so the card tells apart could-not-check, there
are none, and **there are some but none is picked**. The switcher stays on
screen either way, so it is not a dead end.

## A category opens, and every expense is in one place (9 Sep, twenty-eighth pass)

"Allow expansion of these to see all the expenses within each category. Also
somewhere smart there should be a list (which you should be able to choose the
display order of (name/date/amount etc.)) where you can see all expenses in
one place."

### One expense row, drawn in three places

`expExpenseRowHtml(e, showDate)` + `expWireExpenseRows(root)`. The day list, a
category folded open and the all-expenses list are the same row, so the three
cannot drift into describing an expense differently. `showDate` is the only
thing that varies: under a day heading the date is already said, and in the
other two it is the thing you are looking for.

### Pressing a category row opens it, and the mark is what parks it

The row's press USED to be the mute, and one row cannot mean two things. The
mute moved onto the same `-`/`+` mark the day cells and the expense rows
already carry, which makes the whole tab read one way: **press a thing to open
it, press its `-` to leave it out.**

- **The mark is a SIBLING of the row**, not inside it -- a button cannot
  contain a button -- so the two share a flex line and the bar under the name
  ends a mark's width short of the card. Equally on every row, so the
  comparison between them stays honest.
- **A category opens onto exactly the rows its own figure was computed from**:
  its expenses less anything a parked DAY or a parked row has already taken
  out. Otherwise opening a category would contradict the number beside its
  name.
- The fold state sits beside the mute sets and is just as un-persisted: it is a
  view being tidied for now.

### All expenses, in whatever order you want to read them

A card of its own between the month and the balances -- the calendar answers
"when", this answers "everything". Sortable by date, amount, name, category or
who paid, either direction, off one select and one arrow.

- **Every comparison falls back to the DATE and then to `created_at`**, so rows
  that tie on the chosen field keep a stable, meaningful order rather than
  whatever the fetch returned. Sorting by who paid gives each person's own
  expenses in date order, which is the useful reading of that sort.
- **Excluded rows are LISTED, struck through.** This is the place you come to
  see everything, so hiding what a filter has parked would make it the one view
  that lies.
- The order is module state, not localStorage -- `expAvgMode` is held the same
  way, and a sort is a way of reading rather than a setting.
- It is deliberately uncapped and unscrolled: an inner scroller inside a page
  that already scrolls is worse than a long list, and this list is the point.

Driven against five expenses over four days: all five sorts come out right in
both directions (including the paid-by tie-break), the select and the arrow
both drive it, opening Food & Drink shows its two rows and nothing else,
parking a row from inside a category drops it from that category's list and
takes ₩9,000 off the total while the all-expenses list still shows it struck
through, and the mark parks a category without opening it.

## The way back sits under the list, and the mark says the rest (9 Sep, twenty-ninth pass)

"Both in the calendar and in the by category, this one should show up at the
bottom" (the "Count all…" resets), and "we dont need 'Not counted.' simply just
change from a minus to a plus."

- **Both resets moved under the thing they undo.** Over the list, each one
  pushed the whole block down a line the moment anything was parked, so the
  rows you were reading moved under the cursor that parked them. The calendar's
  went under the grid rather than under the whole card: it belongs to the grid,
  and the day list opens below it.
- **"not counted" is gone from both places.** The mark has flipped from `-` to
  `+` and the row has gone pale, which says it twice already.
- **What replaces it on a category row is the PERCENTAGE, which goes.** A
  parked category is not 0% of anything -- it is out of the sum the percentages
  are shares of -- so it shows its own money and nothing else. `₩5,400` on a
  faded row with a `+` beside it.
- `expCategoryNotCounted` was the only string either place used, so the key
  came out of all three tables rather than being left to rot.

## Every expense list pages, and one setting orders them all (9 Sep, thirtieth pass)

"Just like everywhere else, if there is a long list it should be using the page
system we have on the rest of our site", then "this goes too far down
otherwise. And these should also be able to be ordered" -- with a screenshot of
Food & Drink folded open, running off the bottom of the screen.

All three expense lists page at the app's own `PAGE_SIZE` through the app's own
`renderPaginationBar`: the all-expenses card, a category folded open (its own
page per category), and the day list.

- **No "Show more" fold in front of the bar**, unlike the leaderboards and the
  book/job/cert lists. That fold exists for a list sitting BESIDE other content
  it would otherwise bury; these lists are what their own card is for, and
  collapsing "All expenses" to three would contradict the card. The Job Board
  already takes this shape for the same reason.
- **A category's page is forgotten when it closes** and starts at 1 when it
  opens, so a category reopened is read from its top.
- **The day list is tracked by the DATE it was rendered for**, not reset from
  every caller: four separate paths move `expSelectedDate`, and one of them is
  a save.
- **The bar is appended after `innerHTML`, not written into the template**,
  because `renderPaginationBar` builds real elements carrying their own
  handlers.
- **`expSortedExpenses()` is called ONCE per breakdown render**, not per
  category: inside the map it was a full sort of every expense on the trip for
  each row on screen.

### One ordering, two controls

The by-category card gained the same Sort select and direction mark the
all-expenses card has, and **they drive the same pair of values**. Two selects
showing different values for the same-looking thing is the more confusing
outcome, so "how expenses are ordered" is one fact and `expPaintSortControls()`
writes both headers from it every render -- a control that can disagree with
the list under it is worse than no control.

**Re-ordering is re-reading from the top**, so it puts every list back on page
1, including each open category.

**The day list is the one exception and keeps its own order**: within a single
day a date sort says nothing, and the order you logged them in is the one fact
that day has to offer.

Driven with 41 expenses (27 in one category, 12 on one day): the all list pages
5 ways, the day list 2, Food & Drink 3 with 7 on the last page; changing the
sort from the by-category card re-orders both lists, resets every page to 1 and
moves the other card's select with it; flipping the direction from the all
card updates the category card's mark; and closing a category forgets its page.

## Pressing the same day again closes the list under the grid (9 Sep, thirty-first pass)

"If you click the same day again, dont show that bottom row."

The cell's click set `expSelectedDate = dateKey` outright, so once a day was
picked the list under the grid could never be put away -- only moved to another
day. It toggles now, which is the same gesture the trip pills got two passes
ago: the press that selects is also the press that lets go.

Nothing else needed changing -- `renderExpDayAgenda` already hides and empties
the panel for a null date, and the stat tile already falls back to today, which
is exactly what it showed before anything had been picked.

Checked over seven presses: picking, un-picking and re-picking a day, moving to
another day, an EMPTY day (which is the state the report was made from), and
that the day's own `-` mark still parks the day without touching the selection.

## Each category orders itself, and an ordering is a STACK (9 Sep, thirty-second pass)

"The sort should be specific to each category, not be something you have there
at the top level", then "should allow for a multiple sort. Could do category
while also doing date and/or while also doing amount."

### The control belongs to the list it orders

The card-level Sort in "By category" is gone. A folded-open category carries
its own control at its own head and its own levels, kept in `expCatSort[key]`
and **forgotten when the category closes**. Wanting Food & Drink by amount says
nothing about how you read Transport, which is exactly why one control over
both was wrong.

**Category is not offered INSIDE a category**: every row in there has the same
one, so it would be a level that can never break a tie. The all-expenses list
keeps all five fields.

### An ordering is a list of levels

`[{field, dir}, ...]`, applied in turn, each with its own direction. One level
is the ordinary case and is what both start on.

- **The final tiebreak is FIXED at newest-first**, not the last level's own
  direction. Otherwise adding a level would quietly reshuffle the ties
  underneath it, which is the opposite of what adding one is for.
- **Picking a field another level already holds SWAPS the two** rather than
  creating a duplicate or silently dropping one: the number of levels stays
  where the reader put it, and what happens reads the obvious way. Each level
  keeps its own direction through the swap.
- **`+` is offered only while a field is left**, since two levels on one field
  is a second question that can never be asked.
- **The `✕` is `act-off`, not `act-remove`.** It throws away a way of READING
  the list, not a record. Red belongs to the marks that delete something, and
  three of them in a control row would shout at nobody.
- One builder and one wiring function serve both owners; the category's is
  built with `t()` rather than STATIC_MAP, since there is one per open category
  and STATIC_MAP is keyed by a single element id.
- The breakdown groups the open categories' rows in ONE pass and then sorts
  each category's own array, rather than sorting the whole trip per row.

### And a language change now redraws the Expenses tab

`renderAll()` never included `renderExpenditure()`, so the whole tab -- which is
almost entirely generated markup with barely anything in STATIC_MAP -- stayed
in the old language until something else happened to re-render it. A per-open-
category control cannot be in STATIC_MAP at all, so this had to be fixed rather
than lived with. Checked: switching to Korean redraws both stacks (정렬 /
그다음 / 날짜) and the open category survives the switch.

Driven over eleven steps: one level to three and back, the swap, removing the
middle level, category-asc-then-amount-desc giving Dinner/Brunch/Lunch then
Taxi/Metro/Bus, two categories open with different orderings that do not touch
each other or the all-expenses list, and a closed category forgetting its own.

## The category's sort stack sits on the right (9 Sep, thirty-third pass)

"Keep the sort on the right side."

`justify-content: flex-end` on `.exp-sort-row`. It ends where the category
row's own figures end, so the two line up rather than the controls starting a
second column under the name -- and it is where the all-expenses card keeps
its own. flex-end also right-aligns each wrapped line once the stack grows past
one row, which is the case a text-align would not have covered.

## The sort is one menu with a switch, and the list can show what it is leaving out (9 Sep, thirty-fourth pass)

"I dont like this + sign for the sort. There can be a way to turn on multiple
sort. If it is on, when you press something else (like date when amount is
already chosen), then it should just have both chosen in that menu. If multiple
sort is not turned on, then you can only sort for one thing and it changes it
if you click something else", then "there should also be a selector in all
expenses where you can choose to show either included expenses, excluded
expenses, or both".

### One menu, and a switch that decides what a press in it MEANS

No `+`, no `✕`. A button carrying the whole ordering in words and arrows
("Category ↑ then Amount ↓"), and a menu with **Multiple sort** at its head:

- **Off**, the menu is a pick-one: pressing a field replaces the ordering and
  closes the menu.
- **On**, it is a pick-several that remembers the ORDER they were pressed in --
  which is the order the levels are applied in, so the control teaches itself.
  A rank number appears beside each chosen field once there is an order to
  read.
- **No press in the menu is ever dead.** Pressing the field already picked
  flips its direction rather than doing nothing, and with multi on, pressing
  the LAST remaining one flips it too rather than leaving the list with no
  order at all.
- **Turning the switch off keeps the first level** rather than throwing the
  ordering away: the switch changes what a press means, and doing two things
  at once is how a switch becomes a surprise.
- Each chosen field has its own direction arrow IN the menu, so a level's
  direction is changed where the level is.

**Close the menu BEFORE calling commit.** commit is what re-renders, so setting
the flag after it drew the menu open again with nothing left to clear it -- a
pick-one that visibly did not close. Caught by driving it rather than reading
it.

The menu is anchored to the RIGHT edge of its button, since this control sits
at the right of its card and a menu hanging off the left would run off the
page. Which menu is open lives in `expSortMenuOpen` rather than as a class,
because every press re-renders the block the menu is inside.

### Show all, counted, or excluded

A `Show` select in the all-expenses header. Only that list: the day list and a
folded-open category are already about one day and one category, where a filter
on top of the parking marks would be a second thing to keep track of.

- Excluded rows still render struck through in every mode -- the filter chooses
  WHICH rows, not how they read.
- With a filter on and nothing matching, the empty line says so ("Nothing
  matches what you asked to see") rather than the tab's "no expenses logged
  yet", which would be a different and false claim.

## Un-picking the last level gives the standard order back, and the empty line names its own question (9 Sep, thirty-fifth pass)

"If I unclick amount, it should just do the standard order that was already
there", and "this should be smarter. If no excluded, say 'No excluded
entries.' or something".

- **Un-picking the last chosen field hands the list the DEFAULT ordering**
  rather than flipping it, which is what the pass before did to avoid leaving
  the list with no order at all. Date-newest-first is that order, so Date is
  ticked afterwards and the menu goes on saying what the list is really in --
  the tick is not lost, it moves to the thing now doing the ordering.
  `expDefaultSort()` is written once and read by the comparator, both owners'
  initial state and the un-pick, so the three cannot drift into three ideas of
  "standard".
- **The empty line names which question came up empty.** "Nothing matches what
  you asked to see" was true of all three modes and said nothing about any of
  them. Three modes, three different facts: **nothing is excluded**,
  **everything is excluded**, and **nothing is logged at all** -- and the last
  is a different claim from the first two, so it wins whenever the trip really
  is empty.

Checked over five states: nothing parked with Excluded only, everything parked
with Counted only, an empty trip in every mode, and the two combinations that
still have rows to show.

## How the all-expenses list is read survives a refresh (9 Sep, thirty-sixth pass)

"It doesnt save what i have picked", then "if i refresh the site".

The ordering, the multiple-sort switch and the Show filter go to localStorage
(`expListPrefs`) and come back on load.

**This does not contradict the rule that the parking marks are NOT persisted.**
That rule is there because a filter which quietly outlives a reload is how a
total lies to you weeks later -- and none of these three can lie: an ordering
cannot change a figure, and Show is a labelled control sitting right there
saying which of the three it is on.

**The per-category sorts are still not saved**, for the reason they are already
forgotten when a category closes: they belong to a category you have opened,
and there are none open on a fresh load.

**Read back field by field rather than trusted.** This is a string somebody
else could have written, and a bad field name would silently sort by nothing
while a bad direction would sort backwards. Driven through eleven shapes --
unparseable, null, a bare number, `sort` not an array, a bad field, a bad
direction, a duplicated field, one good level beside one bad, nulls inside the
array, a bad `show`, a non-boolean `multi` -- none of which throws, and every
one of which lands on the default for whatever did not survive rather than
taking the list down.

## The exclusions are saved, and a filtered total says so (9 Sep, thirty-seventh pass)

"Save them. But have an obvious way that it shows, if you come back after a
refresh, that there are items excluded."

This reverses the call this file has carried since the category filter was
built -- **and the objection it was based on is answered rather than dropped**.
The reason not to persist was that a total which is quietly filtered is a total
that lies to you weeks later. So the filter now says so, above the figure,
every time the tab is drawn:

> **— 3 expenses are left out of these totals.        Count everything again**

- **Counted in EXPENSES, not in marks.** That is the number the totals are
  actually short by; a parked category is one press and can be twenty rows.
- **English inflects and the other two do not**, so the singular is its own key
  rather than an "(s)" -- the rule at the top of this file, met again.
- **In the edit amber**, above the stat row, inside the card it qualifies. Loud
  enough to be read before the figure under it, quiet enough not to read as an
  error: it is a true statement about the totals, not something going wrong.

### Kept PER VACATION

Two of the three grains -- a date and an expense id -- belong to one trip and
mean nothing on another. `localStorage.expMuted` is `{vacationId: {cats, dates,
ids}}`, loaded when the trip resolves and when it changes, and a trip with
nothing parked leaves NO row rather than an empty one, so the store cannot grow
a key per trip ever opened. Deleting a trip drops its row.

Checked: parking on one trip, switching, parking something else, and switching
back gives each its own back; a seeded store survives a reload; and nine
garbage shapes (unparseable, null, an array, a bare number, a row that is not
an object, `cats` not an array, numbers where ids belong, a mix of good and bad
entries, a row for a trip that is not open) all load as nothing parked rather
than throwing or parking something that is not there.

### And both "count everything again" buttons now mean it

`expAnyMuted()` counts categories too, and the grid's reset clears all three
rather than only days and rows -- two buttons carrying the same words had to do
the same thing. The by-category card keeps its own scoped "Count all
categories", which sits with the rows it resets and says exactly what it does.

## "3 excluded" (9 Sep, thirty-eighth pass)

"Think it's too much yap." Seven words to two.

"3 expenses are left out of these totals" spelled out things the reader can
already see: the mark beside it is the same `-` that parked them, and the
figure it qualifies is directly underneath. **`{n} excluded`.**

It also drops the singular/plural PAIR the sentence needed -- "excluded" does
not inflect, so one key is honest at n = 1 in all three languages, where "1
expense IS left out" against "3 expenses ARE" was two.

Read back in all three: "1 excluded", "3개 제외됨", "3 bị loại".

## The notice is ON the total, and a delete pill is BRIGHT RED (9 Sep, thirty-ninth pass)

"'2 expenses left out' (red text in the total)" and "'Count everything' (green
at the bottom left like everywhere else)."

The amber banner is gone. The two halves of it went where each belongs:

- **The fact is on the figure it is about** -- a red line inside the Total tile,
  under its own label, so the number and what it is short by are read in one
  glance rather than as a strip above the card.
- **The way back is a plain green `linkbtn` at the foot of the card**, which is
  where every other "count these again" in this tab already sits, and it is
  "Count everything" now -- the "again" went from the key, so the grid's copy
  got shorter with it.

**And the singular came back.** "2 expenses left out" inflects where "2
excluded" did not, so English needs its own two keys again; Korean and
Vietnamese hold the same string in both.

### A delete drawn as a solid pill

"All delete buttons on the site in these pills looks stupid as fuck in terms of
contrast", then "should be bright red".

They were the default button fill -- near-BLACK in the light theme and
near-WHITE in the dark one -- with `color: var(--danger)` on top. The theme's
two reds are a brick (#B33B34) and a salmon (#E8827A), so either way the word
sat in the same colour family as the pill under it and read as disabled.

`.btn-danger` is a solid `--danger-solid` (#DC2626) with white on it, and that
token is deliberately OUTSIDE the light/dark pair: red on a button is not a
theme decision. Three buttons carry it -- the expense delete, the vacation
delete, and the account delete, which had been doing this by hand with an
inline `--seal` fill and now shares the one definition.

**Still neutral, and left alone**: the four deletes drawn as `.export-btn` (the
calendar's delete, delete-this-only / delete-all, delete all writing samples).
They are a different control -- a small outlined button -- rather than the pill
that was reported, and turning a two-button choice dialog into two red slabs is
a bigger call than this was.

## Every "Sort by" on the site is the expenses control now (9 Sep, fortieth pass)

"We need to update this sort by in jobs applications and certifications too. We
have a better system now. Update all THIS TYPE of sorts across the site to that
new system we have in expenses."

Four one-field `<select>`s replaced by the menu with the multiple-sort switch:
**job applications, certifications, the job board, and the moderator user
list.** The control stopped being the expenses' own -- `exp-sort-*` became
`sort-*` in the CSS, `expSortMultiple/Then/Asc/Desc` became `sortMultiple`
and friends, and the field labels became ONE family (`sortField<Name>`) that
every list draws from by naming its fields. Eight keys nothing read any more
came out of all three tables.

### What each list gained, and what it kept

| | fields | default |
|---|---|---|
| applications | date, status, company, role | date, newest |
| certifications | date, status, name, issuer | date, newest |
| job board | posted, deadline, title, company | posted, newest |
| moderator | date, name, 2FA, confirmed | date, oldest |

**Every old behaviour is preserved by the value function rather than by the
sort.** Status still sorts in PIPELINE order (`JOB_STATUS_SORT_ORDER`), not
alphabetically. A certification with no completion date is still dated by when
it was added. A job-board listing with NO deadline still sorts last whichever
way that level points -- a `￿` sentinel does it, where an empty string
would put it first ascending. The two moderator booleans read as 1/0, so "2FA"
descending puts the accounts that have it first, which is what its single
option used to mean.

**A field's default direction is per field now**: words go A to Z, a pipeline
goes in pipeline order, and anything countable goes biggest or newest first.
Always-descending was fine when only expenses had this and is wrong the moment
"Company" is an option.

**Every list remembers its ordering** in one `listSortPrefs` store keyed by
list, validated field by field on the way back in.

### Two traps, one of them expensive

- **A `const` used during script EVALUATION must be declared above the line
  that uses it, and a try/catch will hide it.** These lists build their own
  sort state as the script runs (`let jobSort = loadListSort(...)` at the top
  of the jobs block), and the store's key was declared with the control near
  the end of the file -- so it was in its temporal dead zone, the read threw
  ReferenceError, the `catch` returned `{}`, and every list silently started on
  its default. It looks exactly like "it does not save". The store now sits
  above every caller.
- **`python3 -m http.server --directory "$PWD"` is not safe here.** This
  environment flips the working directory between Bash calls, so the server can
  end up serving a different tree -- and then the page silently lags the file
  being edited while every change "does nothing". It cost a wrong diagnosis
  above. Pass the absolute path, and when behaviour contradicts the source,
  `curl` the served file and grep it before believing either.

### Left alone

**The grammar list's sort** is not this type: its options are `default`,
`freq-desc`, `freq-asc` and `favorite` -- two of them a field and a direction
fused into one option, and two of them not fields at all. And the Yonsei
boards' newest/oldest is a direction with no field to choose. Converting either
would be redesigning the control rather than replacing it.

## The name goes on two lines, and the ROOM is what a class card is for (9 Sep, forty-first pass)

### The header cost two rows because the title took one on its own

"On app, shrink this text and put it on two lines, so it's the same height as
the pills and stuff."

The app's name set across the full width was what pushed the six controls onto
a second line: at 393 the brand was 140px and the control row needs 211 of the
353 available, so the row broke. Two smaller lines beside them instead, and the
header is **44px against 79**, as tall as the brand icon rather than as tall as
two stacked rows.

- **The size is SOLVED, not picked**, because the whole point is that the two
  halves share one row at every phone width. Measured, "Productivity" is
  6.32px per px of font size plus 3.5, and what is left for it is the page less
  its 20px padding either side, the 32px icon, the 8px gap beside it, the
  header's own 8px gap and the 211px the controls come to. So 309px of the
  viewport is spoken for and the rest divides by 6.32:
  `clamp(11px, calc((100vw - 309px) / 6.32), 15px)`. It lands at 13.3px on a
  393 phone (6.5px of slack) and on the 11px floor at 375, where it still fits
  with 3px to spare.
- **The break is on the WORD, not on the box.** A wrap that depends on the
  width available is one that comes apart at some width.
- **And the word boxes were already there.** The h1's markup is thrown away:
  `buildTitleMorph` rebuilds it as a `.tl-track` of per-character spans grouped
  into a `.title-word` per word, so putting spans in the HTML did nothing at
  all and the break is one `display:block` on a box that already exists. Worth
  knowing before touching that title again: **read the DOM, not the source.**
- **Its own breakpoint (440px), not the 640 one**, because 440 is where the
  crowding is: the one-line header stops fitting at about 403, and two lines on
  a 600px window would be two lines with half a row of space beside them.
- **The condensed bar is one line by construction**, so the two words go back
  to being one there. Checked: at 393 it is 12.1px on one line with the whole
  name visible, and the desktop is untouched at 28px.

### The class number was the biggest thing on the card and the least useful

"The wrong thing is made big here. The class rooms (i.e. 702 and 106) are
supposed to be big. ISC6236 is the least important."

The day-view card is rebuilt to the order asked for, which is the order you
need it in while you are walking to the class:

| | |
|---|---|
| the class's name | 13px, bold (was 10px, inherited) |
| **the room** | **22px, bold** (was 9px, fourth line) |
| the type (PIC1, ITFM1) | 11px |
| the professor | 11px (was 9px) |
| the course code | 10px, dimmed (was 18px, second line) |

**That order is also what survives the clip, which is the whole reason to
state it as a priority.** A bar is `overflow:hidden`, so whatever sits last is
what gets cut, and the code is exactly what a short bar can afford to lose. A
one-hour class comes out as its name and its room and nothing else, which is
the pair worth keeping.

- **Both height guards are arithmetic on the bar's own box.** The card needs
  its 4px of padding, the 14px the mobile layout reserves above the title for
  the bell and the pencil, the title's 15.6px line, 4px over the room and the
  room's own line: 16.1px at 14px of type, 25.3px at 22px. So **54 and 64 on a
  phone, 40 and 50 on a desktop**, where nothing is reserved at the top.
- **The room SHRINKS to 14px rather than being clipped**, and that is not a
  detail: half a numeral reads as a DIFFERENT room, where small type reads as
  small type. Under even that the card falls back to the week view's compact
  form, which is what a 30-minute class already got.
- Checked at every height a day view really produces on a phone (HOUR_PX is 60
  there): at 180 and 120 every line is whole; at 60 the name and the room are
  whole and the type is where the cut lands; at 40 it is the compact form.
- The week view is untouched: `dayCard` is gated on `isDayView`, so a bar
  sharing its column with an overlapping class is a narrow bar again and gets
  exactly what it got before.

## A page can be deleted, moderators can correct study hours, and every delete is red (11 Sep, forty-second pass)

Six off one message, plus a seventh added half way through it.

### Deleting a note's page

`deleteNotePage`, reached by a red "Delete page" at the far end of the page
bar, in both note editors (course notes and the notebook share the pager). It
is only offered one page at a time: with every page in a row there is no
"this" page to point at. It asks first.

- **A page goes with ONE of the breaks beside it**, or it comes straight back
  as an empty page: the break it ends with (a break is filed with the page it
  closes), or, for the last page, which ends with nothing, the break above it.
- **Through Quill as one 'user' `deleteText`, not the DOM**, so it saves,
  broadcasts and undoes like any other edit. The range comes from
  `Quill.find(el)` + `getIndex`; the last page deletes to `getLength()`.
- The page after slides into its place; off the end, the one before is shown.
  Down to one page the bar hides itself, as it always has.
- Checked on a scratch Quill in the browser: first, middle and last of three,
  the last of two, and an empty last page, each leaving exactly the pages and
  breaks it should. **Pasting `<hr class="note-page-break">` through the
  clipboard puts an empty paragraph before each break**, which shows up in
  `getText()` -- that is the paste, not the delete.

### The page-break button was paper on paper

`svgIcon` strokes `currentColor`, and a Quill toolbar button's colour is the
BASE `button` rule's `--paper`: Quill colours its own `.ql-stroke`, never the
button. So the mark was paper-coloured on the paper-dim toolbar in both
themes. It is `--ink-soft` now, the same as Quill's marks, and Quill's hover
and focus blue still win because their selector is heavier.

### The tab pill follows a resize

The only re-measure on resize lived inside the 150ms debounce that reorders
the tabs, so the pill sat on the old spot for the whole drag and jumped at the
end. A rAF-throttled resize listener now runs `refreshRowSliders(true)` once a
frame, INSTANT -- an eased pill chasing a target that is still moving is the
lag that was reported -- and an instant placement clears any pending stretch
timer, which would otherwise land after it and put the pill back.

- **Not a ResizeObserver on the rows**: a row sized by its own content
  resizes when a tab is chosen, and that would cut the travel short on every
  click.
- Verified with the debounced reorder STUBBED OUT: tab shifted 70px, one
  resize event, one frame, pill at 70, reorder never having run.

### Moderators correct study hours

`sql migrations/admin_study_entries_migration.sql`: `admin_list_study_entries`,
`admin_set_study_entry`, `admin_delete_study_entry`, SECURITY DEFINER behind
`current_is_admin()`, REVOKEd from anon. RLS keeps study_entries own-write and
the admin is not in every circle, so the read has to be an RPC as well as the
writes.

- **The write validates**: known activity keys, numbers only, 0 to 1000. A
  zero is dropped and a day left with nothing is DELETED rather than stored as
  `{}`, which is what `deleteMyDay` does. **No cap on a day's total**: the
  app's own logger has none, and live rows already hold more than 24 hours on
  one activity, so a cap would stop the admin saving a day unchanged.
- **Tested against the live schema in one batch that raises at the end**, so
  all of it rolls back: set, list, upsert, zero-to-delete, delete, and refusals
  for an unknown key, a negative, a string and a non-admin caller; then checked
  that no function and no row was left. Worth reusing: a DO block that
  `RAISE EXCEPTION 'RESULT %'`s its findings hands them back in the error while
  guaranteeing nothing commits. **No explicit BEGIN/ROLLBACK round it** -- an
  aborted explicit transaction can be left open on a pooled connection; the
  implicit one rolls itself back.
- The editor sits under the moderator's account list: account, date, one field
  per activity in its own colour, Save day / Delete day, and that account's
  logged days as chips. Each account row has a "Study hours" link that opens
  it for that account.
- **Every write reloads the dataset** (`scheduleSharedDataRefresh`). Realtime
  cannot be relied on: it is filtered by the same RLS, so the admin hears about
  an edit to an account outside the circle from nobody.
- **A bad entry is reported in place, not re-rendered**, which would put the
  stored hours back over what was just typed.
- **Assumption, stated**: "the self tracked leaderboard stuff like Korean
  study times" was read as the study-hours log the study leaderboards count.
  Books, articles, jobs and certifications are lists of records, not times,
  and were left alone.
- Driven in the browser with the RPCs stubbed: load, a refused negative (no
  call sent, typed value kept), a save sending `{listening: 2, reading: 1.33}`
  with the empty and zero fields dropped, and a delete behind its confirm.

### Every delete is red

- **`.item-meta .linkbtn:not(.act-icon)` is 0,3,0** -- a `:not()` counts its
  argument -- and beats `.linkbtn.act-remove`'s 0,2,0 wherever the two meet.
  So every text delete in a meta row came out celadon: the moderator's
  "Delete account", a syllabus's "Remove", "Remove from trip".
  `.item-meta .linkbtn.act-remove` matches its weight and comes later.
- **`.export-btn.act-danger`**, red text and a red border on hover, on the four
  outlined deletes that were grey: Delete all (writing samples), the calendar
  modal's Delete, and the delete-choice modal's two.
- **`.gram-resource-del` rested in `--ink-soft`** and only turned red under the
  pointer. Red at rest now, with `:hover{background:none}` for the reason
  `.item-del:hover` has one: `button:hover` (0,1,1) outweighs a bare class and
  would paint a dark pill under the pointer.
- The filled `.btn-danger` buttons were already red and are unchanged.
- **The first pass at the grammar ✕ added a rule ABOVE an existing one** I had
  not found, because my grep filtered out lines that begin with `.`. Found by
  walking `document.styleSheets` for every rule the element matches, which is
  the reliable way to ask what is actually colouring something.

### The title hover wears the reader's own colour

`--my-color` on the root, set by `setMyColorVar` wherever the name is painted
in that colour: sign-in, guest, and the colour picker. The letters, the meter,
the runner and the check read `var(--my-color, var(--on))`, so before sign-in
it is the green it always was. Checked by setting a colour, reading all four
computed colours, and clearing it again.

### Checking this app in the preview pane, for next time

- **`preview_start` by name picked up the OTHER project's launch.json**
  (Welcome Korea's `korea-explorer-dev`) with this folder as the working
  directory, and `file://` URLs are refused. What works: a background
  `python3 -m http.server 8791 --bind 127.0.0.1 --directory <absolute path>`,
  then `preview_start({url: "http://localhost:8791"})`.
- **`#appScreen` is `display:none` before sign-in**, so anything measured in
  it reads 0x0. Un-hide it for the measurement instead of signing in.
- **Top-level `let`/`const` are reachable from the page** (`moderatorUsersCache`,
  `notePagers`, `modStudy`), and top-level functions can be swapped for a test
  (`scheduleSharedDataRefresh = ...`, `reorderMobileTabs = ...`), which is how
  the editor ran with nothing sent and the slider ran with the debounce out of
  the way.

## New pages go at the end, pages move and page themselves, and the phone title runs both lines (11 Sep, forty-third pass)

### "New page" adds a blank page at the END

It cut the note at the caret, and `getSelection(true)` on an editor without
focus answers index 0 -- so the "new" page came out as a new page 1
(real-user report). `addNotePageAtEnd` puts a hard break before the last
line's newline and the caret on the new empty last line. **A blank last line is
doubled first**, or the break would carry off the only line the page above
had and leave it with nowhere to type. The button is `buildNotePageAddControl`,
drawn as a sheet with a plus (`ICON.pageAdd`), labelled `notePageAddBtn`.

### Auto pages

A tick and a slider in the page bar, per browser like one-page-at-a-time
(`ptNoteAutoPages`, `ptNoteAutoPageLen`: 500 to 10,000 in steps of 250,
default 3,000), off until asked for.

- **Counted in CHARACTERS, not screen height**: a break is saved into the
  note, and height depends on the width of whichever device is typing. An
  image or a video counts as 400, so a page of screenshots still fills up.
- **Two kinds of break.** `true` is one somebody made; `'auto'` is one auto
  pages made, saved as `<hr class="note-page-break" data-auto="1">` through the
  blot's own `create`/`value`, so it survives `root.innerHTML`, saving and the
  live delta. A re-page takes every auto break out and puts them back greedily
  at line boundaries; a hard break stays put and restarts the count. **A line
  is never split** -- a paragraph longer than the limit is a long page.
- **`Delta.diff`, not `setContents`.** The note is read as units (lines, each
  with its own newline so its list or heading format travels with it, and
  breaks), rearranged, rebuilt, diffed against what is there and applied with
  `updateContents(change, 'user')` -- a small edit that saves, broadcasts and
  undoes like typing.
- **Only on FOCUSED typing**, 700ms after it stops, and never under an IME
  composition (Korean). Opening a note writes `root.innerHTML`, which Quill
  ALSO reports as a 'user' change; `hasFocus()` is what stops a note being
  rewritten just by being opened. Ticking it, or letting go of the slider,
  re-pages the note in front of you once.
- **`notePageRewriting`** is set around every rewrite the pager makes (auto,
  move, new page, delete). Both editors' default-colour listeners check it, or
  moved lines read as freshly typed and get painted in the viewer's colour.

### Moving a page

"Move page ← [n] →" in the bar, one page at a time only (it needs a "this
page"). The field shows where the page is; typing another number and pressing
Enter, or leaving the field, moves it there. **A boundary keeps its auto mark
only between two pages that were already neighbours in that order**; every
boundary a move makes is hard, or auto pages would pour the moved page
straight back into its new neighbours on the next keystroke.

### The bar with one page

It vanished below two pages. Auto pages has to be reachable BEFORE a note has
pages, since making them is what it does, so with one page the bar is that
switch alone (and nothing where the editor is read-only).

### The phone title runs both lines

On a phone the title is two lines (the 440px block), but the ball ran along
the top of the whole track -- over "Productivity" only -- and the check sat past
the end of the longer word. Each `.title-word` now carries its own
`.tl-wrunner`, timed to its own letters (`--w-delay`, `--w-dur` off the same
34ms step as the letters): along the TOP of "Productivity", then along the
BOTTOM of "Tracker", bouncing down and away from the letters (`tl-hop-down`).

- **The check lives INSIDE the last word** now: the same right-hand edge on one
  line, the gap beside "Tracker" on two. The two-line words are
  `width:max-content`, or a block word is as wide as the title and anything at
  its right edge lands past "Productivity".
- **The track-wide runner and bar are hidden on two lines** -- the bar sat
  exactly where the second run goes. Scoped `#topBar:not(.stuck)`, since the
  condensed bar is one line.
- **The per-word runners only animate under `prefers-reduced-motion:
  no-preference` and `:not(.no-anim-title)`**, and are invisible at rest, so
  turning motion off needs no display overrides fighting the 440px block's
  specificity.
- Verified with numbers, not only pictures: every `#appTitleHome:hover` rule
  cloned onto a class, and `document.getAnimations()` paused at set times --
  the ball above "Productivity" at 200ms, under "Tracker" from 420ms, the check
  beside "Tracker" at the end. **A paused-animation screenshot can come back
  as the previous frame**; wait before shooting, and trust the measured rects.

### Checked how

A scratch Quill in the browser: a new page on a normal note, a blank-ending
one and an empty one; last page to first, one step with the arrow, and a typed
number; auto at 500 and then 1,000 with a hard break kept, an idempotent second
pass, auto breaks surviving an innerHTML round trip; a move with auto on that
kept the untouched auto boundary; delete; and the bar's one-page and
several-page states.

## Two sub tabs side by side, a colour for whoever an event is for, and the calendar keeps its view (11 Sep, forty-fourth pass)

### Split view

Drag a sub tab out of its row and drop it on another sub tab, or on the page
beside the one that is open, and the two open side by side, like snapping two
windows (real-user request). Each half has a slim bar with its name and an X
that closes it; the other half takes the width back. Choosing a third sub tab,
or another main tab, closes both.

- **Only from the static sub-tab rows** (the five `SPLIT_GROUPS` rows), never
  the hover fly-out on the main nav ("not the pop-out ones"). Reversed in the
  forty-sixth pass, below: the fly-out splits too. **Only with a mouse or a
  pen**: on touch the same gesture is a scroll, and a phone is never wide
  enough anyway.
- **"At least 2x app size on the width" is read as 2 x 640 = 1,280px**, 640
  being where this app turns into its phone layout, so each half gets at least
  the width the desktop layout was drawn for. That was an assumption, and it is
  one constant (`SPLIT_MIN_WIDTH`). Narrower, the drag does not start and a
  notice under the tab says why; a window shrunk below it while split goes back
  to one tab and says so.
- **Where it lands.** Onto another sub tab: those two, in the row's own order.
  Onto the page below the row: the half under the pointer, beside whatever is
  open (nothing if the dragged tab IS the one open: there is no partner). With a
  split already open, a third tab replaces the half it is dropped on, and one
  open half dropped on the other side swaps them. A translucent snap preview
  glides to the half it will take, the Windows way, and the tab it would pair
  with gets a ring. **The ghost sits beside the pointer, not on it**: centred on
  it, it covered the very tab being dropped onto, ring and all (the first
  screenshot of a drag showed exactly that). Escape cancels.
- **Nothing moves in the DOM.** The panel becomes a two-column grid
  (`.tab-panel.split-on`) and the two sections are placed on it by class
  (`.split-left`/`.split-right` on row 2, the sub row across row 1). A moved
  section would reload any embed in it and lose an editor's place.
- **Every sub tab still goes through its own switch function.** Each
  `switch*SubTab` starts with `splitSwitchGuard(group, view)`: one of the two
  open halves chosen again is a no-op, a third ends the split and switches as
  normal. The split drives the switch functions itself under `splitBypass`, so
  each half gets exactly the side effects a click gives it (a render, a fetch),
  and the entering half goes last so it is the row's `.active`; the other
  half's tab gets `.split-active`, painted the same, and the travelling pill
  steps aside while both are lit. `switchTopLevelTab` ends a split for another
  main tab and `applyTabVisibility` ends one whose half was just hidden; either
  way the tab that was open before the split is the one kept.
- **`var splitView`, not `let`.** The switch functions consult it and some can
  run before that part of the script is reached; a `let` read then is a
  ReferenceError, a `var` is undefined, which reads as no split.
- **The animation is `grid-template-columns` itself**, 1fr 0fr to 1fr 1fr and
  back (the gap with it), which current browsers interpolate. The entering half
  fades and slides in from its side; a closing half fades while its column
  folds. It settles on a TIMER, not `transitionend`: a browser that cannot
  interpolate tracks never fires one. Pills inside the halves (month/week/day)
  are re-measured every frame, and once settled a `resize` is dispatched,
  because a split changes every width in two sections exactly the way a window
  resize does.
- **A drag swallows the click its release would fire**, and a press that never
  travels 6px stays an ordinary click.

### "Use Roxy's color"

With only Roxy ticked under For, the add-event form still offered "Use my
color" and nothing else (real-user report). `renderEventColorLinks()` draws one
link per person the event is FOR, "Use my color" for the adder and "Use Roxy's
color" beside it, by the rule `addEvent()` itself follows: nobody ticked, or no
For field at all (a birthday, a non-core account), means the event is yours.
Redrawn on every tick, by `rebuildForUserSelect()` and the kind toggle, and on
a language change.

### Roxy's Notes shortcut is desktop only

The icon runs a macOS Shortcut that lives on her Mac, so on her phone (the
installed app included) it could only fail (real-user request). Hidden unless
`(hover: hover) and (pointer: fine)` (`isDesktopPointer()`), asked the way the
language picker asks rather than as a width, and re-checked when that answer
changes.

### Convert every amount

"Show in" only ever added a small ≈ line under each figure. A "Convert every
amount" tick beside it (shown once a currency other than the trip's own is
picked) makes the chosen currency REPLACE the trip's in every figure: the stat
tiles, the categories, the month cells, every row, the balances and the
settlements, all through `expShowMoney`/`expShowMoneyCompact`. **Display only.**
The rows keep the amount as typed, in the trip's own currency, so going back to
Original shows the input to the cent however often the view is switched, and
the expense form still takes that currency, its label now naming it ("Amount
(KRW)"). Until a rate has arrived the figures stay as typed rather than being
guessed. Per device, like the currency itself (`expDisplayFull`).

**Month-cell amounts under 1,000 are whole units now** ("$11", not "$11.00",
which is six characters and does not fit a cell). That also changes a trip kept
in USD or EUR, which had the same problem before any conversion.

### The calendar remembers month/week/day

Per device (real-user request: day view on the phone last time should be day
view next time). `ptCalViewMode` in localStorage, read where `calViewMode` is
declared and written by `setActiveCalViewBtn()`, which every change of view
already goes through, the notification and deep-link jumps included.
`renderCalendarTab()` already draws whichever mode it finds.

### Checked how

In the browser at 1,440 and 1,100 wide with a faked signed-in pair:

- a split settling at 691 + 691 with both bars and labels, the pill hidden and
  both tabs dark; the X folding one half back to 1,400 with every class gone;
- a drag driven by synthetic pointer events: onto the Calendar tab (preview on
  the right half, ring on the target, source dimmed), onto the page's right
  half and then its left (the pair flips), Escape cancelling, and the click the
  release fires swallowed;
- a third sub tab and another main tab each ending it with the right tab kept,
  and Korean's Log + Grammar splitting with Notebook ending it;
- the too-narrow notice on a drag at 1,100, and a split opened at 1,440 closing
  itself, with its notice, when the window went to 1,100;
- the colour links in all three languages, Roxy's link setting her colour, and
  a birthday leaving only "Use my color";
- ₩19,500 showing as $14.04 with Convert every amount on, month cells $11 / $3 /
  $1.7k with the exact figure on hover, the stored rows still 15,000 and 4,500,
  and Original putting ₩19,500 back; the form label "Amount (KRW)";
- day view surviving a reload, heading included;
- the Notes icon shown on the desktop pointer and hidden in the phone emulation
  after a reload (pointer coarse, no hover).

Three things worth keeping from the testing:

- **`profiles` maps an id to a NAME string** (`nameFor` returns it as is), and
  colours live in `profileColors`. A fake profile OBJECT prints "[object
  Object]" through every `nameFor`, which looked like a bug in the new code
  and was not.
- **Synthetic PointerEvents dispatched on `document.body` reach window
  listeners, and `elementFromPoint` still reads the real layout**, so a drag
  can be driven entirely from the console.
- **The old `/tmp/claude-501/verify.mjs` was gone.** It was rebuilt in the
  session scratchpad (syntax, ids, STATIC_MAP, and now every `t('key')` against
  all three tables). That last check found one pre-existing gap:
  `t('lblNewNotebookTitle')` exists in no table, so that label prints its raw
  key. Flagged as a task of its own rather than fixed here. (Fixed in the
  forty-fifth pass, below.)

## The Notebook's title label printed its own key (11 Sep, forty-fifth pass)

`buildNotebookMetaFieldsHtml`, the panel that opens from a notebook note's pen
and from clicking its name above the editor, labelled the title field
`t('lblNewNotebookTitle')`. That is a DOM ID, not an i18n key: `STATIC_MAP`
maps the ID `lblNewNotebookTitle` to the key `lblNewLecture`. No table has the
ID as a key, so `t()` handed it back and the label read "lblNewNotebookTitle"
in all three languages.

It is `t('lblNewLecture')` now ("Note title", "노트 제목", "Tiêu đề ghi chú"),
the key the static add form and the course-notes twin `buildNoteMetaFieldsHtml`
already use. Reused rather than given an entry of its own, because it is the
same field (`lecture_title`) saying the same words, and a second key is three
more strings to keep in step.

**A `STATIC_MAP` key is an element ID. What goes into `t()` is the value on
the right of it.**

Checked: the `t()` sweep (every literal key against all three tables) now
finds nothing missing anywhere in the file. In the browser the panel was
generated under each language and rendered in place in the Notebook editor
card: its title label matches the add form's in English, Korean and
Vietnamese, and the colour label and both buttons are translated too.

Two more things about the preview pane, on top of "Checking this app in the
preview pane": port 8791 can already be held by another session's server (any
free port works), and while the pane is HIDDEN the page reports `innerWidth` 0,
so everything lays out zero wide. `resize_window` with a custom size gives it a
real viewport. The first screenshot after that was a stale blank frame; the
next one was true.

## The halves resize, swap and scroll on their own, and the fly-out splits too (12 Sep, forty-sixth pass)

Four requests on top of the split view from the forty-fourth pass, all
real-user: "resize the split views to a certain extent ... with a thing in the
middle to move it like on windows", "swap the two sides they're on with the
click of a button", "make it so the scrolling happens independently on either
one side of the split screen", and "allow for doing split view by using the
pop-out sub tabs too".

### A divider you drag

- **The gutter is a grid TRACK now, not a gap**: `minmax(0,Afr) 22px
  minmax(0,Bfr)`, with `.split-divider` in the middle column. A column-gap
  cannot hold an element, and the divider has to be something you can press.
  It is also why the halves are 689 + 689 at 1,440 wide where the forty-fourth
  pass measured 691 + 691.
- **The share is scaled by `SPLIT_FR` (10,000).** Fr values that add up to less
  than 1 leave the rest of the track EMPTY rather than sharing it out, so 0.62fr
  and 0.38fr would leave the halves narrower than the panel. As 6,200fr and
  3,800fr they fill it. The open and close animations run on the same numbers.
- **It stops at 35% and 65%, and no half is ever narrower than 440px**
  (`SPLIT_RATIO_MIN`, `SPLIT_PANE_MIN_PX`), whichever is stricter. At 1,440 wide
  the percentage decides; at 1,300 the 440px floor does (35% would be 433px). A
  window resized while split re-clamps the share, and one resized under 1,280
  closes the split as before.
- **Double-click evens it.** On the keyboard it is a `role="separator"` with
  `aria-valuenow`: the arrow keys move it 2% (5% with Shift), Home and End go
  to the two limits, Enter evens it.
- **The handle stays in the middle of the SCREEN**, not of the divider: it is
  sticky at `50vh`, since a divider as tall as a long section would otherwise
  put its grip wherever the middle of that section happened to be.
- A drag is pointer-captured and moves the columns at most once a frame.
  `body.split-resizing` holds the resize cursor over everything, stops text
  being selected, and takes pointer events off iframes, which would otherwise
  swallow the move the moment the pointer crossed an embed.

### Swapping

A round button on the handle swaps the halves, and **each half keeps its
width**: the share becomes `1 - ratio`, so Calendar at 65% on the left becomes
Calendar at 65% on the right, still 896px. The two slide past each other (a
FLIP translate, 360ms), and each keeps its own scroll position.

### Each half scrolls on its own

- **Each half is exactly as tall as the screen below where it starts**
  (`--split-pane-h`, set by `splitFitPanes()`), with its own scrollbar, so the
  page has nothing left to scroll. Measured from where the halves sit on the
  PAGE, which does not depend on how far it is scrolled, then shaved by whatever
  the page would still overflow by; never under 320px (`SPLIT_PANE_MIN_H`).
  `overscroll-behavior: contain`, so reaching the end of one half does not
  scroll the page.
- **Each half's bar (its name and X) is sticky** at the top of its own box.
- **Opening a split takes the page back to its top**, and what the reader was
  looking at in the half that stays goes INTO that half, the same distance
  under its bar. **Closing one puts the kept half's place back on the page.**
  Both go through one anchor, `splitCaptureAnchor` / `splitRestoreAnchor`. A
  sub tab or main tab taking over the screen skips it, since that is not a
  place anybody is going back to.

Three things about that anchor, each of which put the reader somewhere else:

- **It is taken BEFORE the close animation.** The kept half grows to the full
  width on the way out and its content re-wraps, so an anchor measured after
  that is measured on a page the reader never saw. `closeSplitPane` takes it
  and hands it to `endSplitView`.
- **It is the first card STARTING in the upper half of the view**, and only
  failing that the card whose tail is at the top. The tail of the tall calendar
  card re-wraps to another height with the width, and anchoring on its top
  moves everything under it by the difference.
- **The top bar compacts when it sticks: 164px at the top of the page, 99px
  pinned, at 1,440 wide.** A restore always starts at the top of the page (an
  open split has nothing to scroll), so the scroll that puts the place back is
  the scroll that pins the bar, and it moves the very edge it was measured
  against: a card put back 40px under the bar landed 105px under it. The
  restore now runs up to three passes and calls `updateTopBarStuck()` between
  them, which is what the scroll event would run a frame later.

### The fly-out splits too

This reverses the forty-fourth pass's "only from the static sub-tab rows", on
the same person's word. The items in the main nav's hover fly-out drag exactly
like the row's:

- **The fly-out is held open for the length of the drag** (`splitFlyoutHold`).
  `showTabFlyout`, `hideTabFlyout` and `scheduleTabFlyoutHide` all do nothing
  while it is set, so leaving the fly-out to drop on the page does not take the
  thing being dragged away, and no other tab's fly-out can open in its place.
- **Out of another tab's fly-out, the drop switches to that tab first** and
  opens the split there, beside whichever of its sub tabs was open. The snap
  preview is drawn over the page on screen, since that is where the pointer is.
- **Onto another item of the same fly-out** pairs the two, as onto another tab
  in the row. Escape cancels and puts the fly-out away.

**One fly-out bug that was already there**: `showTabFlyout` turns the fly-out
visible two frames later, so its transition runs, and a hide inside those two
frames was undone by it, leaving a fly-out on screen that no tab owned and
nothing would ever put away. It turns visible only if it is still that tab's.

### Checked how

In the browser at 1,440, 1,300 and 1,100 wide, with the faked signed-in pair
from the forty-fourth pass:

- a split settling at 689 + 689 with the divider between them, and the columns
  genuinely interpolating (727 / 652 at 190ms of the transition);
- both halves 636px tall and the page overflowing by 0; the left half scrolled
  300px with the right half and the page not moving, its bar still at the top;
- the divider dragged to 60% (827 / 551) and on past the end, stopping at 65%
  (896 / 482); double-click back to 689 / 689; the keys giving 52%, 65%, 35%
  and 50%;
- the swap: Expenses left and Calendar right at 35%, each half exactly the
  width it was, and the scrolled half still scrolled;
- at 1,300 wide the share re-clamped to 35.5% with the narrow half exactly
  440px; at 1,100 the split closing with its notice;
- Grammar dragged out of Korean's fly-out while on Home: the fly-out held
  open, a ring on Writing when over it, the preview over Home's left half, and
  on release Korean on screen with Grammar | Log. Then, on Korean, Notebook
  dropped onto Writing in the fly-out, giving Writing | Notebook, and Escape
  mid-drag putting everything away;
- the anchor, with a card planted on purpose: "Add to calendar" 40px under the
  half's bar comes back 40px under the pinned top bar (it was 105); the
  calendar scrolled 500 picks "Add to calendar" at 38 and returns it at 38;
  reopening from a page scrolled 650 puts "Your deadlines" 218px under the
  half's bar, as it was under the top bar; and a half scrolled only 40 returns
  the calendar card at -38;
- a fly-out shown and hidden in the same frame still hidden, and ownerless, two
  frames later; an ordinary show still turning visible.

Worth keeping from the testing:

- **The fly-out takes no pointer events for two frames after it is shown**, so
  a test that shows it and drags onto an item in the same tick drops onto
  whatever is underneath, and reads as a broken drop. Let a frame go by (a
  screenshot does it).
- **Test an anchor with a card placed on purpose.** The first check used
  whichever card happened to be at the top, the 514px calendar card, and a
  67px miss on it read as noise; a card set 40px under the bar showed a
  constant 65px, which is what pointed at the top bar.
- **A screenshot taken straight after an instant scroll can show the fixed top
  bar painted where the page was**, half way down a blank screen. The numbers
  were right and the next frame was too.
- **index.html has 46 em dashes that predate these passes**, so a patch guard
  that fails on any em dash fails on the file, not on the patch. Compare
  counts.
- The spawned session's fix (`187c8dd`, the forty-fifth pass above) was
  committed to main in this same directory while this pass was in progress,
  and this commit sits on top of it.

## The language menu opens in front and closes again, and a colour can be kept for later (12 Sep, forty-seventh pass)

### The language menu

Two reports about one control: "the menu goes behind the tabs for a second
instead of in front of it" and "if I click it again, it does not close".

- **Behind the tabs: the press squeeze.** `.lang-switch:active` scales the pill
  to 0.94 and eases it back over 0.15s. While it has a transform the pill is a
  stacking context of its own, so the menu's z-index 300 is counted INSIDE the
  pill and the pill as a whole sits under `.tabs` (z-index 60). The menu opens
  on the release, exactly while the pill is easing back, so it opened behind
  the tabs every time. `.lang-switch.lang-open{z-index:300}` gives the pill's
  own layer the menu's height for as long as the menu is up.
- **Never closing: listeners that piled up.** `buildLangSwitch` empties and
  refills the SAME container on every language change and on every window
  resize (the resize handler rebuilds all three switches), and it ADDED its
  click and keydown listeners to that container each time. One click then ran
  every toggle: the oldest closed the real menu and opened its own detached
  copy, the newest found its menu shut and opened it again. The handlers are
  properties now (`onclick`/`onkeydown`), cleared at the top of every rebuild
  together with the role/tabindex/aria attributes, so a rebuild into the touch
  branch (the native select) leaves nothing behind either.
- `langMenuOpen` is a `var` now: buildLangSwitch reads it, and a `let` read
  before its line has run is a ReferenceError (the reasoning `splitView` uses).

**Anything rebuilt into the same element must set its handlers as properties or
remove the old ones.** `innerHTML = ''` clears the children, never the
listeners on the element itself.

### Favourite colours

Real-user request: "You should be able to set some favorites for your default
color... when I click my name, I should be able to save it, so I can change my
color, and still have that one later."

- **Clicking your name opens a popover** (`#whoColorPop`) instead of the OS
  colour picker directly: the colour you have now (swatch and hex) with a
  star to save it, your favourites as swatches (press one to wear it; the one
  you are wearing is ringed), and "Pick a new color". That last row IS the
  native `<input type="color">`, same id `#whoColorPicker` and same `change`
  handler, moved from lying invisibly over the name into the popover. The OS
  picker is now one press further away, which is the price of having
  somewhere to keep colours.
- **The star toggles.** A saved colour reads "Saved" with a filled star, and
  pressing it again un-saves it. Each swatch also has an x under a pointer; on
  touch there is no hover to show it on, so the star is the way there: wear
  the colour, then un-star it.
- Newest first, **twelve at most**, the oldest dropping off. Hex only,
  lowercased and de-duplicated (`cleanFavColors`).
- **Stored on the account in `profiles.favorite_colors`**
  (`sql migrations/favorite_colors_migration.sql`, `text[]` default `'{}'`,
  written with the same own-row update `profiles.color` uses). Whether the
  column exists is read off the `select('*')` row (the key is there or it is
  not), so the app works before the migration has run: the list lives on the
  device in `ptFavColors:<uid>`, and the first load that finds the column
  merges the device's list into the account's and pushes it, ONCE. After that
  (`ptFavColorsSynced:<uid>`) the account's list is the truth, or a colour
  removed on one device would come back from another device's old copy. A
  guest keeps them on the device.
- **The name pill is hovered and pressed directly** (`#whoName:hover` and
  `:active`, were `#whoNameWrap:hover #whoName`). It had to be asked through
  the wrapper while the input lay over it; asking the wrapper now would light
  the pill whenever the pointer is over the popover.
- **Closed** by a press anywhere else (in the CAPTURE phase, so a control that
  stops its own click, like the language pill, still closes it), by Escape, by
  the name again, and by opening the language menu, which works both ways.
  `#whoNameWrap.pop-open` carries z-index 300 for the same reason `.lang-open`
  does.

### Checked how

In the browser at 1,440 and 390 wide with the faked signed-in pair, and
`supabaseClient.from('profiles')` stubbed to record what would be written:

- the language pill rebuilt three times (as three resizes would), then opened,
  shut and opened again; `elementFromPoint` over the part of the menu that
  hangs across the tab row hitting the menu at rest and with the pill scaled to
  0.94, and hitting the TABS with the pill scaled and `.lang-open` taken off,
  which is the reported fault reproduced; at 390 wide (the touch emulation) the
  pill rebuilt as the native select with no role and no onclick left over;
- the favourites: the empty state; Save storing `["#4f7563"]`; a new colour
  picked (#B5485D, star off, the favourite not ringed); the favourite worn (the
  name back to #4F7563, star on, ringed); the x removing it; two saved, newest
  first; not one `favorite_colors` write without the column, and one `color`
  write per change;
- the popover hit-testing as itself over the tab row, pressed or not; closing
  on an outside press, on the name, on Escape and on the language menu; Enter
  on the name toggling it;
- the column path: a device list of two merged under an account list of one and
  pushed once, the synced flag then set, and the next load taking the
  account's list alone; fourteen saved kept to twelve; "#ABCDEF", "nope",
  "#abcdef" and "#4F7563" cleaned to two;
- at 390 wide the popover inside the screen (138 to 366).

Worth keeping from the testing:

- **Two screenshots showed the popover missing while it was open and on top**
  (computed opacity 1, nothing clipping it, `elementFromPoint` hitting it).
  Another stale frame from the preview pane: after a resize and a second's
  wait it painted. Measure before believing a screenshot that something is
  not there.
- `sql migrations/favorite_colors_migration.sql` is new this pass and was
  **applied to the live database on 12 Sep** (project `kbqwitmxpmkueryjsyip`,
  "Korean", via apply_migration as `favorite_colors`). `authenticated` already
  holds a table-wide UPDATE grant on profiles, and the own-row update policies
  cover a new column on the same row, so no grant was needed. A device that
  saved favourites before this carries them up on its next load.

## The Type list reads in the order the calendar is used, and a colour link is painted in that colour (12 Sep, forty-eighth pass)

Two small ones off one screenshot each.

### The order

"In the calendar the order here should be Event, Deadline, Birthday, Course,
Pill cycle." It was Deadline, Event, Course, Birthday, Pill cycle, which is
the order the kinds happened to be added in rather than any order a reader
would look for them in.

- **The edit panel's list moved with it**, so the choices do not reshuffle
  between adding something and editing it. That one is written as literal
  `<option>` markup rather than built from the same array, so the two can
  drift; they agree today and it is worth checking both whenever a kind is
  added.
- **The default is still Deadline.** `rebuildEventKindSelect` falls back to
  `'deadline'` explicitly rather than to the first entry, so reordering the
  list cannot change what a fresh form opens on.
- **The edit panel now draws a Pill cycle option for an event that already IS
  one.** It never had one, so the select matched nothing, fell back to its
  first entry and saving silently rewrote the pill cycle as that kind. Before
  this pass that was Deadline and after it would have been Event; either is
  wrong, and it is only reachable by the one account that has pill cycles, so
  it had gone unnoticed. Drawn from `ev.kind === 'pill'`, not from
  `isPillCycleAccount()`, so the option only ever exists where it is already
  the answer.

### The colour links

"The 'Use my color' and 'Use Roxy's color' buttons should be in my color and
roxy's color respectively." Both wore `--celadon-4` like every other
`.linkbtn`, so the one control whose whole subject is a colour said nothing
about which colour it would give you.

- **Through a custom property (`--use-color`), not an inline `color`.** An
  inline colour beats `.linkbtn:hover` -- inline style wins over any selector
  -- so painting it directly would have taken the hover feedback away
  entirely. The rule reads the property with the old value as its fallback, so
  every other linkbtn is untouched.
- **Hover SOFTENS rather than shifting hue** (opacity 0.78). The ordinary
  hover moves celadon-4 to celadon-3, and moving the hue is exactly what this
  link cannot do: the hue is the whole point of it.
- **`applyMyColor` repaints it**, alongside the name pill and the popover. The
  link names a colour, so it has to follow a change of that colour in the same
  frame. The repaint sits before the Supabase write, which is awaited.
- **The raw colour is used, with no legibility correction**, which is what
  `#whoName` and `--my-color` already do. A colour picked dark enough to
  vanish on the dark theme would vanish here too; that exposure is the app's
  existing one rather than a new one, and inventing a one-off contrast rule
  for two links would be the drift.

### Checked how

In the browser at 1024 wide, light and dark, with a fake two-person state
(Kristoffer `#6FB894`, Roxy `#C2748E`): the add form's list comes out
`event, deadline, birthday, course, pill` with `deadline` selected; the edit
panel's comes out in the same order and a pill event keeps `pill` selected;
the two links compute to `rgb(111,184,148)` and `rgb(194,116,142)`; and a real
hover holds the colour at opacity 0.78.

## The form opens on the kind you last added, and "public" said too much (12 Sep, forty-ninth pass)

Four off two screenshots.

### The default kind

"It should default to what you picked last time you added something." It opened
on Deadline for ever, so anybody who mostly adds events re-picked Event every
time.

- **Written on a real ADD, not on the select's own change.** It sits inside
  `insert(...).select()`'s success branch, so a kind picked and then abandoned
  is not remembered, which is what the request says.
- **Per DEVICE, keyed by the ACCOUNT** (`ptLastEventKind:<uid>`), the shape the
  calendar's own view mode already uses: the phone and the desktop are rightly
  allowed different answers, and two people sharing a browser are not handed
  each other's.
- **It is applied by the rebuild that runs AFTER sign-in**, and that is forced
  rather than chosen: `rebuildEventKindSelect` also runs from `applyLanguage`
  before sign-in, where `currentUser` is null and the account's key cannot be
  read. That second call already existed for the same reason (the Pill cycle
  option), so the note there now records both.
- **`eventKindTouched` is what stops it overwriting a live choice.** Without it
  the post-sign-in rebuild would put the stored default back over a kind just
  picked by hand; with it, a language change keeps whatever is on screen.
- **A rebuild that MOVES the kind calls `updateKindFieldVisibility`.** The
  fields on offer follow the kind, so landing on Birthday without it would have
  shown the deadline layout until the select was touched. Only when it moves:
  every other rebuild is a relabelling.
- **The stored kind is validated against the kinds on OFFER**, so a stored
  `pill` on anyone else's account falls back to Deadline rather than selecting
  nothing.

### Three off the form's own row

- **"Public" claimed more than it means.** Nothing here is ever visible outside
  the circle, so the choice is who IN the circle sees it (real-user report:
  "this 'public' only means your circle could see it, so it is kind of a weird
  phrasing"). It reads **Shared with your circle** / Private, using each
  language's own word for the circle (내 그룹, nhóm; see `hLinkedCircle`). The
  select is sized to its own widest option now, with the shared 150px as the
  floor, in the add form and the edit panel alike.
- **The reminder field carries no worked example.** "e.g. 45m, 3h, 2d" is gone,
  key and all: that box is reached by pressing the trigger a second time with
  the preset list already open, which is deliberate enough not to need the
  format spelled out in it.
- **The "+ Add reminder" trigger is drawn as one of the form's controls.** It
  wore a dashed pill in a row of solid 6px boxes and was the only thing there
  that looked like it belonged to something else (real-user report: "it's kind
  of weird only that button is different from all the other ones"). Same
  border, radius, ground, padding and type as `.field select`. The CHIP keeps
  its pill: a reminder that is set is a state rather than a control.
  - **`white-space: nowrap` and an explicit `line-height`, both measured.**
    Without the first the label wrapped to two lines inside its own box (54px
    against the selects' 39); without the second it came out 2px short, because
    a `<select>` takes its line box from the font's own and a span does not.

### Checked how

In the browser at 1024 and at 375, light and dark, with a two-person state: a
fresh account opens on Deadline, `rememberEventKind('event')` then a
pre-sign-in plus post-sign-in rebuild lands on Event (the pre-sign-in one
correctly cannot see it), a hand-picked Course survives a language rebuild, a
stored `pill` comes back as Deadline on another account and as Pill cycle on
the right one, landing on Birthday hides the time field and relabels Title as
Name, another uid on the same browser reads empty, all three controls in that
row measure 39px tall, and the wider Visibility select overflows nothing at
375 (216px inside a 375px screen).

## Every box grows now, and something comes out from behind the Add button (12 Sep, fiftieth pass)

### The grow, extended to the boxes

"This one makes the box bigger when hovering over. Maybe we need to simply add
that functionality to ALL boxes across the site." So the vocabulary the words
have had (1.08 on hover, 0.98 on press) now covers every box the reader can
press or type in: the form's inputs, selects and textareas, the auth fields,
the primary button in each form (`.log-form > button`), and the
`.export-btn` / `.icon-pill-btn` / `.day-toggle-btn` / `.person-filter-btn`
families. **201 controls across the app**, counted with every panel laid out at
once.

Two things differ from the words, and both are forced rather than chosen:

- **The origin is the CENTRE.** A word grows from where it starts reading; a
  box in a row of boxes has neighbours on both sides, so growing about its
  middle spends half the growth into each gap rather than all of it into one.
- **The factor is 1.04, not 1.08**, and that number is measured: the widest
  control in the app is **320px** and `.log-form`'s own gap is **10px**, so the
  words' 1.08 would put a hovered box **13px into its neighbour** where 1.04
  stays inside the gap (6.4px) at every size on the page. A proportional scale
  cannot serve a 16px mark and a 320px input at one factor, which is why this
  is its own tier rather than more selectors on the existing rule.
- **`:focus` is excluded outright.** A box being typed in is the one place this
  reads as a fault rather than as feedback.

Three things had to be kept out of it, each for its own reason:

- **The PIN gate's digit boxes** (`.pin-digit`) carry their own transform, both
  as a class and as keyframes, and a transition on the same property is the
  fight this file already records three times over.
- **Containers are not boxes.** A card is 984px wide; 4% of it is 39px of
  overflow, and nothing on the page is pressable at that size anyway.
- **The reminder trigger needed the word rule turned OFF explicitly.** It
  carries `.cal-seg` as well (`wireEventReminderAddTrigger` adds it so the
  inline picker works), and that selector is the MORE specific of the two --
  (0,3,0) with its two `:not()`s against this rule's (0,1,0) -- so it would
  have gone on growing 1.08 from its left edge in a row of boxes growing 1.04
  about their middles. Source order would not have saved it; `:not(.reminder-
  add-trigger)` on the word rule is what does.

`body.no-anim-ui` and the reduced-motion block name all of it, or the one
switch that is meant to stop this would leave the bigger half running.

### The add courier

"Whenever you add a big thing where you entered a lot of information, when you
press Add, a little guy comes out from behind the button, grabs the A in Add,
turns it around and sucks up all the information, puts it in a suitcase, before
sprinting off the screen to the right." That, exactly, in `addCourier()`.

- **It only ever runs on a SAVE.** Every one of the nine add handlers calls it
  from inside its own `if(!error && data)` branch, which is also before that
  handler clears its form -- so the pills he collects carry what was really
  typed, and a courier is never seen carrying off an add that did not happen.
  The study log is the one that goes through a shared function rather than
  writing its own row, so `logStudySession` returns whether it logged anything
  and the button asks.
- **The letter is a COPY, and the real one is only made invisible.** Taking the
  glyph out of the button would reflow it mid-animation, so the first character
  is wrapped in a span, hidden, and drawn again in the overlay at the same
  rect. The button keeps its own width and reads "dd" while he has the A.
- **It is the first CHARACTER of whatever the label says**, code-point safe, so
  it is the A of Add and the 추 of 추가. Checked: `Array.from('추가')[0]` is 추.
- **Turned around, an A is a funnel** -- apex down, legs open upward -- which is
  what the information can then be poured into. That is the whole reason the
  brief's "turns it around" is also the thing that makes the next beat read.
- **He is drawn facing LEFT, at the form**, and is flipped (`scaleX(-1)`) at the
  moment he turns to go. One element carries the run and another the flip: one
  element cannot animate one property from two places.
- **He is hidden behind the button by a CLIP on a gate**, not by paint order
  (an overlay cannot be behind a button in a card). The gate starts at the
  button's own right edge and runs to the edge of the window, so a single
  `clip-path: inset(0)` hides him while he is still behind the button AND takes
  him off screen at the far end, with no value that has to be kept in step with
  the animation.
- **He stands to the right, because that is the way he leaves.** Measured at
  375px: every Add button in the app has at least 44px of room there and he
  needs 34, so the guard against there being no room is a guard rather than a
  case anybody meets.
- **Its own animation group**, `add`, so it can be turned off on its own like
  the header, the title and the interface -- four `ANIM_GROUPS` now, with its
  own row, label and hint in all three languages. Off, nothing runs at all: no
  overlay, and the button's own glyph is never touched.

### Two things that cost real time

- **`fill: 'both'` on a DELAYED animation holds its first keyframe from time
  zero**, which overrides whatever earlier animation is meant to be showing
  until its turn. Measured by stepping the timeline: the courier stood fully
  out from behind the button at t=0 and the letter sat in his hand before he
  had reached for it, because the run and the tip were filling backwards over
  the emerge and the grab. **Anything with a delay fills FORWARDS only.**
- **The letter was invisible the moment it left the button.** It was drawn in
  the button's own ink, and the Add button is a solid near-black pill with
  near-white text -- so its ink is exactly the colour of the page behind it
  (and the reverse in the dark theme). It crosses from the button's ink to the
  page's as he lifts it, both read at run time, so it is right in both themes.
  Same trap this file already records for a hard-coded white.

### Checked how

- **The sequence cannot be watched at speed in the preview pane**: it freezes
  the document timeline unless something is painting, so six screenshots in one
  batch returned six copies of one frozen frame. Every frame was verified by
  **stepping `currentTime` by hand** with the cleanup timers stubbed out, which
  is deterministic and is what caught the `fill` bug: A on the glyph at t=0,
  him clipped behind the button, out and hopping at 200, the letter in his hand
  at 400, the pills staggered at 93/35/4/0/0/0 percent opacity at 700, the
  letter at the case at 1700, running at 1900.
- **The drawing was judged at 3.4x**, by scaling the layer about itself, since
  the pane cannot crop a screenshot. Light and dark.
- The whole path end to end: it starts, a second call while it is running does
  not stack a second one, and after 3.2s the layer is gone, `acBusy` is false
  and the button is back to a single text node reading "Add".
- 201 controls picked up by the new hover rule, one clash found (the reminder
  trigger, above) and fixed, and the pin boxes confirmed to keep their own
  transition rather than this one.

## An application fills itself from a link, the courier keeps the letter, and a delete asks (12 Sep, fifty-first pass)

### Fill from AI, on the application form

**Reworked the same day, on the same person's word**, and the second shape is
the one to keep: one **Copy prompt** beside Add application, and the answer is
pasted into the **Company field**, which has parsed a whole pasted application
since long before any of this existed. So there is no second button and no
labelled field of its own, and the model replies with the LABELLED BLOCK that
field already reads rather than with JSON.

- **The prompt makes the model end with one fixed sentence, word for word**
  ("Paste this whole answer into the Company field of the application form"),
  which is how the answer says where it goes -- and `parseJobPasteText` drops
  that line on the way in. It matches the exact sentence, and falls back to the
  opening words for a model that rewords the tail. Checked all three ways:
  exact, reworded, and absent.
- The date is deliberately NOT asked for: when you applied is a fact about you,
  and the paste already fills it with today.
- Everything below is the first shape, and the reasoning still holds.

#### The first shape, and why the prompt is written the way it is

"Add a copy AI prompt button that either just needs the link to the job
posting or the name of the company/position to fill out the log an application
fields." The machinery the book and the article forms use is already generic --
a `[data-ai-scope]`, a `data-ai-field` per input, and `aiFillControlsHtml(kind)`
-- so the job form joins it rather than growing its own.

- **A job posting is not a bibliographic record**, so `aiPromptFor` has its own
  `job` branch asking for the three things the form can actually hold: company,
  role, link. It also tells the model NOT to answer with a careers homepage, a
  search page, or an aggregator where the employer has its own posting, which
  is what an LLM reaches for when it cannot find the real one.
- **`aiSeedFor(kind, scope)` is new, and it is what made the request
  expressible**: the old code seeded the prompt from `[data-ai-field="title"]`
  alone, and a job has no title. For a job it prefers the LINK where there is
  one (that is the whole posting; a company and a position are a description of
  it), falls back to "Role at Company", then to whichever of the two is filled.
- **`title` is deliberately NOT mapped to the role** in the shared FIELDS
  table: it already means a book's title, and in a job scope there is no title
  field for it to find, so a stray one is skipped rather than landing in the
  wrong box. `employer`, `position` and `job_title` are mapped, since an LLM
  reaches for those.
- Checked with real answers: a fenced JSON reply with prose around it fills all
  three; the alias keys fill all three; "I could not find that posting, sorry."
  fills nothing and says so; and a BOOK answer pasted into the job scope fills
  nothing rather than something.

### A delete asks first

"Add a warning when you try to remove job applications/certificates. currently
there is no warning." `confirm(t(...))` inside the delete FUNCTION rather than
on the button, so every path that can delete one goes through it -- the shape
`deleteCourse` already had.

**Books and articles were in exactly the same state and got it too**, so all
four owned lists behave the same rather than two asking and two not. Each
message says what goes with the row: an application's uploaded CV stays in
storage and keeps its short link, and a book's or an article's NOTES go with
it, which is the part worth knowing before pressing Delete.

### The courier, second pass

Four reports, all of them right.

- **The letter must not change colour.** It was drawn in the button's own ink
  and then crossed to the page's, because the Add button is a solid near-black
  pill with near-white text (and the reverse in the dark theme) -- its ink is
  exactly the colour of the page behind it, so a bare letter is invisible the
  moment it leaves. It is **a chip OF THE BUTTON** now: the button's ink on the
  button's own fill, with a 4px radius. Nothing about it changes on the way,
  it is legible wherever it goes, and it reads as the piece he tore off. Only
  its FILL fades, over the last of the flight home, which is what turns it back
  into the letter on the button rather than a chip sitting on top of one.
  Measured at four moments: ink `rgb(24,25,27)` throughout, identical to the
  button's own.
- **The letter comes back.** He keeps it while he runs (it travels with his
  hand) and **throws it in from off screen**, arcing, spinning two whole turns
  so it lands upright exactly on its own glyph. Stepped: it leaves at 2400 with
  him and lands at [559,374], which is the glyph's own home to the pixel. What
  goes in the suitcase is the INFORMATION, which is what the brief said --
  three drops now pour out of the funnel into the case while he tips it, so the
  pour is something you can see rather than something implied.
- **He has some substance.** Not a stroked stick figure: a filled torso with
  arced shoulders, a head with a CAP (its peak out to the left, the way he
  faces), a bag strap, hands, feet, and a case with a clasp -- with the details
  **knocked out in the page's own ground**, the trick the checkbox tick and the
  train's windscreen already use. The knockouts are a CSS class, not a
  `fill="var(--paper)"` attribute: a `var()` in a presentation attribute does
  not resolve.
  - The chip came down from 1.45 to 1.3 and his reaching hand went up and out
    (5.4, 8 rather than 7, 10.6), because at 1.45 a 15px letter is 22px wide
    against a 30px figure and it covered his head.
- **The form is not emptied until he has taken the information off it.** It was
  cleared the moment the insert returned, so the pills flew out of fields that
  were already blank. Every add handler's own clear block now goes through
  `acClear(fn)`: the courier decides WHEN (at the moment the last pill lands in
  the funnel), the handler still owns WHAT. **With no courier out it runs at
  once**, so nothing about a form depends on the animation being on -- checked
  with the group turned off, with no room for him on screen, and with a second
  add fired while one was already running (one courier, and the second
  handler's own clear still ran). Measured: the title field still reads
  "Dentist appointment" at 1100ms and is cleared at 1206.

## He looks before he jumps, and he carries the letter and nothing else (12 Sep, fifty-second pass)

Two reports off the courier, and the first one reverses the fix from an hour
earlier.

### "Just the A"

"The guy who appears takes the BACKGROUND of the A. Should not. Just the A."

The pass before this made the letter **a chip of the button** -- its ink on its
own fill -- and that was the right answer to the previous report ("the A
switched color") and the wrong object. So the constraint is worth stating
plainly, because it is what makes this awkward: **the Add button's own ink is
exactly the colour of the page behind it**, near-white text on a near-black
pill, and the reverse in the other theme. One flat colour cannot read on the
button AND on the page, which is why the first attempt cross-faded and the
second carried a fill with it.

**What resolves it is that the letter does not have to exist for the whole
run.** It is a bare glyph in the PAGE's ink, `visibility:'hidden'` until he
takes it, and there are two one-frame handovers:

| | |
|---|---|
| `outEnd`, the frame he reaches | the carried letter appears, the button's own letter is hidden |
| `total`, the frame it lands | the carried letter is hidden, the button's own letter comes back |

So the button keeps its own letter in its own ink right up to the moment it is
lifted off, one flat colour covers the whole carry, and nothing anywhere
changes colour. **Both handovers happen while the letter is moving fastest** --
leaving his hand's reach, and landing out of a two-turn spin -- which is what
makes a swap read as a continuation.

- The element's box is now exactly the glyph's rect (no 3px bleed, no radius),
  it takes no `backgroundColor`, and the throw-back keyframes no longer animate
  `background` at all.
- Both timers are cleared in the final cleanup, beside the three that were
  already there, so an interrupted run cannot leave the button's own letter
  hidden.
- Measured at seven moments across the run: `backgroundColor` is
  `rgba(0,0,0,0)` throughout, `color` is `rgb(237,237,239)` throughout and
  equal to the page's own ink, and **exactly one A is on screen at every
  step** -- hidden with the glyph visible up to 960, visible with the glyph
  hidden from 1000.

### The peek

"It should be a bit slower animation at the start. He peeks his head out from
behind the add pill to peek around at what was written and ONLY THEN does he
jump out."

`AC_T` gained `peek: 300` and `look: 380`, so the run is 680ms longer before
anything else happens, and the head is its own `<g class="ac-head">` with
`transform-origin:15px 12px` -- the NECK, which is a point in the drawing, so
it needs `transform-box: view-box` and its origin in view-box units, the same
rule the legs and the case's lid already follow.

Three animations on it: out past the clip edge, a scan along the form
(-14 degrees, then +6, then settling), and back onto his shoulders as the rest
of him arrives. His jump is delayed to `peekEnd` and every downstream delay
hangs off `outEnd` rather than `AC_T.out`.

- **His resting pose is written on the element** (`guy.style.transform`) rather
  than filled backwards from the jump's first keyframe, because a delayed
  animation that fills backwards holds that keyframe from time zero -- which is
  the trap this file already records: **an animation with a delay fills
  `'forwards'`, never `'both'`.**
- **The lean is 31px, and that number is the clip edge.** The gate starts 4px
  past the button's right edge and he rests with his own box 8px short of it,
  so nothing below the neck can show: measured, the torso's right edge is 18.6
  px behind the edge and the case's lid 9.2. A 31px lean puts **10 to 13px of a
  12px-wide head** past it, i.e. all of it including the cap's peak, which
  points left at the form he is reading.
- **The head's left edge stays BEHIND the clip edge for every frame of the
  peek and the scan** (-3.1 to -0.4px, checked every 50ms), so there is never
  daylight between the head and the pill. That is the difference between a head
  coming out from behind something and a head floating beside it, and the
  rotation in the scan is what could have opened one.
- Stepped and looked at, at 4.5x: at 400 and 640 the capped head is out beside
  the pill at two different angles with no body showing, and at 820 the whole
  figure is standing beside the button with its case.

### Two traps in the harness, both of which produced a confident wrong reading

- **`.ac-head` is INSIDE `.ac-top`**, so a rect taken on `.ac-top` is the
  group's, and once the head has leaned out that rect is the HEAD. An earlier
  measurement read as "the torso is 12px past the edge during the peek", which
  would have meant the body was showing; it was the leaned head all along.
  Measure the torso's own `<path>`, or work it out from the view-box.
- **`documentElement.style.zoom` cannot be used to look closely.**
  `getBoundingClientRect` comes back in zoomed pixels while `window.innerWidth`
  does not, so `addCourier`'s own "is there room to the right of the button"
  guard compares two different units and refuses to run at all. A
  `transform: scale()` on the LAYER is the way: the clip scales with the
  drawing, so the picture stays faithful.
- And re-running him by hand needs the button's label put back to one text node
  and `acBusy` cleared, because the cleanup that does both lives in a timer the
  harness stubs out.

## The A is lit by what is behind it, he jumps on what is in his way, and the peek is a pose (12 Sep, fifty-third pass)

Three reports, and the first two passes at the letter were both wrong for the
same reason: I measured the one theme that cannot show the fault.

### "The A is switching colors again"

It was, and the arithmetic says exactly why. In the LIGHT theme the Add button
is a near-black pill (`rgb(30,31,34)`) with near-white text, and the page is
near-white with near-black ink -- so the button's own glyph is near-WHITE and
the carried letter, drawn in the page's ink, is near-BLACK. The handover at the
grab flipped one to the other. **The pass before this checked it in the dark
theme, where the page ink and the button's ink happen to be the same
near-white, so there was nothing to see.** Same class of mistake this file
records for the colour wheel's seam: a fault reported on one surface has to be
reproduced on that surface, and checking the case that cannot show it is
checking nothing.

**There is no single ink that is right in both places, so the letter is drawn
TWICE and neither copy ever changes colour**: the page-ink copy underneath, and
a button-ink copy CLIPPED TO THE PILL over the top of it (`inset()` at the
button's own rect, with `round` at its own border radius). Over the button you
see the button's ink, off it you see the page's, and on the way out the letter
SPLITS at the pill's edge -- which is what a letter crossing from a dark pill
onto a light page actually looks like.

- **Both handovers with the button's own glyph happen while the letter is
  wholly inside the pill**, so the copy showing there is the button-ink one,
  identical to the glyph it replaces. Measured at every step: at 1129 and 1131
  the letter's rect is inside the button's, at 1250 to 2600 it is clear of it,
  and at 4169 it is inside again.
- Two copies mean every letter animation has to drive both, hence `animateA`.
  One `a.animate` left behind would tear the two apart.

### He jumps on what is in his way

"He is running through text like 'copy prompt', if there is any text in the
way, he should jump on it a bit, so it slightly squishes it before he runs off."

`acSteps` reads the page for it rather than being told: anything with text in
it, ahead of him, standing at his own level (its top above his feet and its
bottom not more than 34px above them), leaf-most, and far enough apart that one
hop cannot run into the next. So it works from every Add button in the app
without a single thing being named.

- **The hop is keyframed against the run's OWN EASING, not against distance.**
  `acEase` is the run's cubic-bezier evaluated as a timing function and
  `acRunOffsetAt` inverts it by bisection, so the landing lands on the thing
  rather than beside it. Without that the leap is timed by how far he has to
  go, and the run's easing is slow at the start and fast at the end.
- **Each of the four moments has a MINIMUM of its own**, and that is what makes
  it read: whatever he jumps on is usually the pill standing right beside the
  button he came out of, so the geometry alone put the whole leap inside the
  first THIRTY MILLISECONDS of the run. A leap, a stretch along the top and a
  drop off the end each take time to read whatever distance they cover.
- **The hop rides on a WRAPPER.** The figure's own element carries the run and
  the svg inside it carries the turn, so a third animation on either of those
  transforms would simply replace one of them. Same for the letter, which is in
  his hand and hops with him.
- **The thing he lands on squashes about its own BOTTOM edge**, 5% wider and
  16% shorter, then rebounds. Measured on Copy prompt: 75.3x14.5 to 79.1x12.2
  at the peak and back to 75.3x14.5, with its own `transform-origin` put back
  in the cleanup.
- **A springy timing function over the whole squash reads its own offsets
  through that curve**, which crushed the squash into the first twenty
  milliseconds and left the REBOUND where the squash should have been (measured
  before the fix). It is linear overall with the curve on each keyframe.

### "His peeking looks stupid"

It was: the whole head translated 31px out from a body that stayed put, so what
appeared beside the pill was a head with no neck, no shoulder and nothing under
it. **Leaning the whole figure out instead cannot work, and that is arithmetic
rather than taste: his case is drawn nine units further right than his head, so
any lean about his feet brings the CASE out first** (it only loses that race
past about 36 degrees of tilt, which is a figure falling over).

So the peek is **its own pose**, drawn rather than derived: the same head and
cap as the figure's, with its back quarter still behind the pill, shoulders
wider than the head with a neck's worth of daylight between the two, and the
body running on down to be cut off by the pill's own bottom edge. It emerges,
cranes back over the pill to read the form, and **ducks in BEFORE he jumps
out**, so there are never two of him at the edge at once.

- **HE IS THE SAME INK AS THE BUTTON HE COMES OUT FROM**, and that was the
  other half of why it read as a lump: a near-black figure abutting a
  near-black pill has no silhouette at all. Exactly the fault this file records
  for the little train, which is drawn in the colour of the line it rides and
  had to be outlined in white to be seen on it. Every drawing is now laid down
  TWICE, the first copy stroked wide in the page's own ground (`.ac-halo`):
  invisible against the page, and a rim that separates him from anything dark
  he is over or against. He also stands 2px clear of the pill's edge.
  - **The rule has to name the SHAPES, not the group** (`.ac-halo *`): a
    presentation attribute on a child beats a value inherited from its parent,
    so `stroke="currentColor"` on each path would win over a stroke set on the
    `<g>`.
  - **Everything is in the svg twice now**, so `guy.querySelector('.ac-lid')`
    found the HALO's lid and opened the rim without the case. Both open.
- **The hand is drawn ON the pill in the PAPER colour** (`.ac-grip`), not
  beside it in ink: fingertips curled round a corner are on the near face of
  what they are gripping, and three pale marks on a near-black pill read at
  this size where three dark ones beside it are three more pixels of ink. It
  shares the peeker's animations and its PIVOT, named in its own box, or the
  hand swings away from the head it belongs to.
- The whole thing inverts for free in the dark theme, where the pill is
  near-white: measured, the rim and the fingers come out `rgb(24,25,27)`, which
  is that theme's own paper.

### Checked

Stepped frame by frame in the LIGHT theme, which is the one that shows the
letter: the peek at 430, the crane at 600, the duck at 780, standing at 1000,
the grab at 1130, the leap at 2500, the squash at 2650, the letter home at
4169. Then run once with REAL timers end to end: no layer left behind, the
label back to "Add application" with one child node, `acBusy` false, and the
Copy prompt button's own `transform-origin` and rect back to what they were.

**And the test server can serve a stale copy of index.html.** Half an hour went
into "acSteps returns nothing" when the file on disk was right and the browser
was running the copy from two patches earlier -- `acSteps.toString()` is what
named it. Reload with a `?v=<n>` that has not been used before.

## He comes out on the LEFT, runs beneath the button, and the peek is the same model (12 Sep, fifty-fourth pass)

The whole staging, rewritten to the script Kristoffer wrote out: "Just his head
should stick out, and a hand grabbing the button so he can look around just for
a little bit. Then he goes back in, comes out from the left, grabs the A, sucks
it all up, runs beneath the button and out to the right and then throws the A
back in." Everything below supersedes the fifty-third pass's own peek, which
came out round the button's right edge as a bespoke drawing.

### It hangs together because everything he wants is on the left

He used to stand to the RIGHT of the button, which is the side he leaves by and
the side nothing else is on. On the left are the letter he takes (the A is the
first character of the label), the form he empties, and the room to work in.

- **He is MIRRORED** (`scaleX(-1)` written on the svg, not animated), so he
  faces the button, the letter and the way out all at once. Every anchor on the
  drawing reads from the other side of its own box (`AC_W - AC_HAND.x`), and
  the turn at `turnAt` is gone -- he came out facing the way he leaves, so that
  beat is a wind-up rather than a spin.
- **The letter's flight is now a short hop to his hand** rather than a reach
  across the button, and the pills fly in from the fields beside him.

### Running beneath the button is ONE clip changing sides

The gate is everything LEFT of the button to begin with, so he is hidden while
he is behind it and comes out from its left edge. At `crossAt` -- the one moment
his own box is inside the button's span, so he is hidden whichever side is
showing -- the gate is moved to the far side of the button and his own `left`
is moved by the same amount, since he is placed in the gate by viewport
coordinates and the run is a transform on top of that. **No hole-shaped clip,
no second copy of the figure, and no frame where the swap can be seen.**

- **`crossAt` is read off the run's own easing**, the same `acRunOffsetAt` the
  hop uses.
- **The letter goes behind the button with him**: its page-ink copy carries the
  same clip and changes sides with it, and the copy drawn ON the pill stands
  down for the length of the run -- otherwise the A crosses the button on its
  own, or worse sits printed on it beside its own label. Both come back for the
  flight home, which crosses the page AND the pill, so the clip is dropped
  altogether at `backAt`.
- **The button has to be able to hide him**, so `r.width >= AC_W` joins the
  guard, along with his own width of room to the left.

### The peek is the same drawing, and the clip does all the work

"Why don't you use the same model? Just his head." Its own gate is the space
ABOVE the button, no wider than the button itself: one `inset(0)` then shows
whatever rises past its top edge and hides every part of him that is still over
the pill. He stands on the button's own baseline inside it, so this is the
figure in its ordinary pose at its ordinary size, rising 11px and dropping
back. **No second drawing to keep in step with the first, and no leftovers.**

- **-4px is what puts his head and his hand there at once.** His raised hand is
  drawn at the same height as his head, so at that one offset the head clears
  the top edge and the hand lands ON it. Measured: head 6.55 of its 8.5 above
  the line, hand centre 2px above it.
- **He looks about on the model's OWN neck joint** (`.ac-head`, origin 15px
  12px in view-box units), which is what that group was drawn for.
- **acPeeker and acGrip are gone**, and with them the bug that made this
  round's report: the grip was a sibling of the layer with no gate of its own,
  so "hiding" it by translating it left did nothing and it sat on the button
  for the remaining three seconds. **Anything that is hidden by a clip has to
  be INSIDE that clip.** Three pale lines left on the button is what that looks
  like.

### And `acSteps` only takes what is genuinely in front of him

Starting on the left puts him standing on top of the field beside the button,
which qualified as something to jump on -- and the hop then fired while he was
behind the button, squashing something with nobody on it. The test is his own
far edge now (`q.left < fromX + AC_W`), not the target's.

### Checked

Stepped through the whole run: hidden at rest, head-and-hand over the top edge
at 430, ducked by 780, out on the left at 1000, the A in his hand at 1350
(button reading "dd application"), invisible behind the button at 2560 with the
A clipped away with him, out on the right at 2720 and straight onto the Copy
prompt pill, and the A flying home at 3400. Then once with real timers end to
end: no layer left behind, the label back with one child node, `acBusy` false,
and the button he stepped on back to 75.3x14.5 with its own transform-origin
restored.

### Members rides in the Overview heading's own corner on a phone (12 Sep)

"The Members in expense should be in the right corner, same line as the
Overview when you are on the App version." It was the last item in the row of
currency controls, which on a desktop puts it at the far right of the heading's
own line and on a phone leaves it stranded below them.

**Ordered rather than moved**, so there is one of each in the document:
`.exp-head` is the row, the button is a child of it rather than of
`.exp-head-controls`, and `order` puts the controls before it on a desktop and
after it under 640px, where the controls also take `flex-basis:100%` and drop to
their own line. Measured at both widths: at 1024 the row reads Overview,
controls, Members with Members ending on the row's own right edge (981 of 981);
at 375 Overview and Members share the first line (both at y 421, Members
260..332 against a row ending at 332) and the controls take the two below.

## One ink for the letter, a slower throw, and a peek you can actually see (12 Sep, fifty-fifth pass)

"The A still doesnt retain its font color as it should when he picks it up, and
the throw back in animation is way too fast. And when he looks around, make his
head come out a bit more, looking from side to side. Right now you can barely
see what is happening."

### The two-copy letter was answering the wrong question

Last round drew the letter TWICE -- the page's ink underneath and the button's
ink clipped to the pill -- so it was "lit by whatever is behind it" and split at
the pill's edge on the way out. That is a defensible picture and it is not what
was asked for either time: the letter he picks up off the button has to still be
the letter that was on the button, and a handover at the pill's edge is exactly
the switch the report calls a switch.

**So it is ONE copy in ONE ink, and the ink is the button's own `color`.** What
makes that legible off the button is a RIM in the button's own
`backgroundColor`, and the reason that works is arithmetic rather than luck:
the Add pill is `--ink`, on a page whose ground is `--paper` and whose text is
`--ink`. **That one value is at once invisible ON the pill and the page's own
ink OFF it.** Over the button the letter is the solid glyph the button draws;
over the page it is the same glyph, in the same colour, outlined in the page's
ink. Neither value ever changes, and both are read off the button rather than
named, so it holds in either theme -- verified: light is `rgb(245,245,246)` on a
`rgb(30,31,34)` rim and dark is exactly the mirror, `rgb(24,25,27)` on
`rgb(237,237,239)`, identical at all five sampled moments in both.

**The rim has to be sized against the GLYPH'S OWN STROKE, and the first try was
three times too wide.** Measured on a canvas in the button's own face and
weight, the A's strokes are **1.9px at 14px** -- so the 1.6px rim I started with
buried a 2.5px stroke under 4.2px of rim, and the letter read as a dark mark
whatever colour its middle was. Which is the very complaint, arrived at from the
other direction. Six candidates were rendered at 1:1 and magnified nine times
with `imageSmoothingEnabled = false`, which is the only honest way to judge this
(the preview pane downscales a screenshot, so a 14px glyph cannot be read off
one): the balance that reads as a light letter with an edge round it rather than
as a dark one is a rim of about **0.38 of the carried scale**. `AC_A_RIM` 0.65
against `AC_A_HELD` 1.7 leaves 1.1px of rim against a 3.2px stroke.

- **`AC_A_HELD` went 1.3 to 1.7** on the same evidence: the rim needs room
  round the strokes, and a funnel somebody is pouring into wants to be readable
  anyway. It still starts and lands at scale 1, which is what lets it hand over
  to the button's real glyph invisibly.
- **A text-shadow, not `-webkit-text-stroke`.** A text stroke is centred on the
  outline and so eats half its width out of the glyph, and `paint-order` on HTML
  text is not worth betting on. A shadow is painted BEHIND the text, so the
  letter itself is untouched at any size or rotation.
- **The clip now has four states instead of two copies.** It takes in the pill
  as well as everything left of it to begin with (the letter starts on the pill
  and is picked up from it), tightens to the button's LEFT edge at the run, and
  changes sides with his gate at the crossing. `pillClip` and the second copy
  are gone.

### The throw home was 500ms for 540px

Doubled to **1000ms**, with the beat before it up from 200 to 260. The letter
crosses about half the window and turns twice on the way; at 1080px a second
there is nothing to see.

### The peek: 6.55px of head was not a peek

Measured against the button's own top edge, the old pose put **6.55 of his 8.5
head** over it, which is why "you can barely see what is happening" is the right
report. It is **14.9px now** -- the whole head and the top of his shoulders --
and the look runs over 620ms rather than 380.

**What made that affordable is giving the raised arm its own shoulder joint.**
At the old height his hand landed on the edge for free, because his hand is
drawn at the same height as his head; eight pixels higher it would have been
waving in the air, and the hand ON the button is half of what was asked for two
rounds ago. So `.ac-arm-b` is a group on its own origin (13, 15.4) and swings
**down** by as much as he rises. **The angle is derived, not picked**: -47.4
degrees is the rotation about that shoulder that takes his hand from 7.4 units
above it to 0.6 below, which is the same 8 his body has gained. The arm is
rigid, so it also reaches further out doing it -- which is what somebody hanging
off a ledge does with it. Measured: the hand sits **2px above the edge at both
heights**, so the grip is exactly as it was.

- **His head and shoulders stay one shape.** The torso's shoulder arc is a
  semicircle peaking at y 10.9 and the head's own bottom is 11.95, so they
  overlap on the centre line by a pixel and there is no neck gap to show at any
  height. Checked before raising him, since a floating head is what raising a
  head usually buys.
- **A head that only TILTS reads as a wobble.** It slides the way it is looking
  as well (-24 degrees with -2.6px, then 20 with 2.2), and it **HOLDS at each
  end**: a glance is a stop, not a sweep, and the hold is most of what makes it
  readable at this size. The head's centre travels 8px across a 30px figure.
- **Barely a bob while he is up there**, 1px either way, because he is holding
  on to an edge and his hand cannot slide about.

### Checked

Stepped frame by frame at eleven moments through the peek (hidden at 0, up and
gripping by 170, 14.9px of head at 340, the head at its left hold at 588 and its
right at 762, ducked by 1150) and at thirteen through the carry: the letter's
colour and rim are the same two values at every one of them, in both themes, and
the clip is `inset(0 377.9 0 0)` before the run, `inset(0 501 0 0)` at it,
`inset(0 0 0 646)` past the crossing and `inset(0)` for the flight home. The hop
and the squish still ride on the single letter (one animation on `.ac-hop`, the
420ms squash on the thing he lands on). Then once with real timers end to end:
no layer left, the label back as one text node, `acBusy` false, and no
`transform-origin` left on anything.

- **A frozen transition read as the theme not applying.** The Add button's
  computed background came back as the LIGHT theme's `--ink` immediately after
  `body.dark` was set, which looks exactly like a token that does not swap. It
  is the 0.13s colour transition reported at its start value while the pane was
  not painting -- the trap this file already records for `body`'s own
  background. Screenshot first, measure after.

## Four beats to the peek, a funnel aimed at what it catches, and the row waits to be delivered (12 Sep, fifty-sixth pass)

"Now you just make him throw his head back. Just make him look to one side,
then the other side, then up, then go back down, then go out. And the A he
sucks everything in with should have a 45 degree angle, since he sucks
everything up from there. The A coming back animation is still way too fast.
Also there is no animation of the text actually disappearing when he sucks it
in... Also the thing that it adds shouldnt be added right away, when the A
comes back it should shoot it out to that position."

### A rotation about the neck IS throwing the head back

The report names the fault exactly, and it is a fact about flat drawing rather
than a tuning problem: **a 2D rotation cannot turn a head, it can only tip
one.** Last round's look was ±24 degrees of rotation, so what it drew was a
head nodding forward and then thrown back -- which is what was reported.

So the two SIDE beats are almost pure SLIDE (-4.2px, then +3.8px, with 7 and 5
degrees of lean for life), and the big rotation is kept for the one beat it
really means. The cap's peak sits left of the neck, so turning the head
clockwise LIFTS it, and a raised peak is a chin up: **looking up is
rotate(+20deg)**, and nothing else in the sequence goes near it.

**Four beats, each of which moves and then HOLDS**: one side, the other side,
up, back to centre -- then duck, then out, in that order (real-user request).
`look` went 620 to 820ms to pay for it. The holds are most of what makes it
readable: without them, four poses inside eight hundred milliseconds are one
wobble.

- **LINEAR overall with the easing on each keyframe.** This file already
  records the rule from the hop's own squash, and it bites harder here: an
  overall `ease-in-out` re-reads the eight offsets through its own curve, so
  the four beats stop being equal and a hold between two identical poses stops
  landing where it was written. Measured before and after -- with the overall
  easing the right-hand hold read 3.3 degrees at its start and 10.1 at its end,
  i.e. it was not a hold at all; linear, it is 5.0 at both.
- Measured at the beats: neutral (head centre 582.9, 0 degrees), left hold
  (578.2, -7), right hold (587.1, +5), up (rot +20 with the head 21.2px clear
  of the button's edge against 14.9 at rest), neutral again, then hidden.
- **The body holds still through the side beats** and stretches up 1.6px on
  the one where he looks up. He is holding on to the edge, so his hand cannot
  slide about.

### The funnel is aimed at what it is catching

Upside down an A is a funnel with its mouth straight UP, which is the one
direction the pills never come from. It is **45 degrees off that now, toward
the side the fields are on** -- so the mouth faces them (real-user request:
"should have a 45 degree angle, since he sucks everything up from there").

**DERIVED from the bits' own centroid, not picked**: a form whose fields sit
the other way round tilts the other way. Everything downstream follows from
that one number -- tipped into the case at `aFunnel + 100`, carried at `+140`,
and **landed at a whole number of turns** (`round((aFly + 320) / 360) * 360`)
rather than at a fixed 720, which would have left the letter lying on its side
in the mirrored case. Measured: 0 to 225 over the grab, held at 225 for the
whole collection, 325 at the run, and 720 -- upright -- on landing.

### The throw home: 500, then 1000, then 1700

Third report on the same number. 540px in 500ms is 1080px a second and in 1000
is 540; at 1700 it is 320, which is a thrown letter rather than a streak. The
spin over that flight is one turn, not two.

### The text actually leaves the field

"There is no animation of the text actually disappearing when he sucks it in."
There was not: the pill was a copy that flew away while the words sat in the
field until the handler emptied it all at once. Now the field's own INK fades
out under its pill, staggered with it -- and only the ink, so this is
decoration over data that is already saved, exactly as the report says.

**And whether it comes back is ASKED of the field, not listed.** The handlers
each clear their own fields and they do not all clear the same ones: the study
form empties the hours and deliberately keeps the date and the activity. So at
`bitsEnd`, after the handler's own clear has run, a field that is now EMPTY
simply gets its colour back under an empty box, and one that still holds its
value is faded back in -- which reads as him having taken a copy rather than
the value. Measured, stepping the fields' own animations: date 0.875 at 1990,
0.44 at 2060, gone by 2130; activity gone by 2200; hours gone by 2260; then at
2390 hours is empty with its ink back while the other two fade 0.353, 0.8, full
by 2650.

### What was added waits to be delivered

`acReveal(fn, target)`, beside `acClear` and with the same contract: the
handler owns WHAT is rendered and the courier owns WHEN, and with no courier
out it runs at once, so nothing about any list depends on the animation being
on. **All nine add paths go through it**, each naming the list its row belongs
in (`bookList`, `articleList`, `jobList`, `certList`, `courseFullList`,
`lectureList`, `notebookList`, the visible calendar grid, `entryList`).

The A lands on the button and a row-shaped **packet** is thrown out of it to
that list, arriving as the row itself is rendered -- so the packet and the row
are one object changing hands rather than two things appearing. Measured with
real timers: the packet left the button at 5412 and landed on `entryList`'s own
top edge (681 against a target at 680.5) at 5772, and the render fired at 5892.

- **A target that cannot be seen gets no packet**, just the render: a collapsed
  tab, an empty list, a list off the bottom of the screen. A parcel flying to
  somewhere nobody is looking would only delay the row.
- **`logStudySession` no longer renders.** It could not: the courier has to be
  out before the render can be held, and that is decided after it returns. Both
  timer paths (the study timer and the writing-sample timer) render for
  themselves now.
- **Two backstops, and they are the point.** The cleanup runs the pending
  reveal and cancels every field fade whatever else happened. A list left
  un-rendered or a field left transparent is the one way this animation could
  cost somebody something, so neither may depend on a callback having fired.
- **A second add while one is in flight renders the first list immediately**
  rather than dropping it: the two can be different lists and only one can be
  held.

### The cost, stated plainly

The whole run is now **5.34s to the landing and about 5.9s to the row**, against
3.9s two rounds ago. Most of that is what was asked for (the 700ms on the throw
and 200 on the look), but a list that does not update for five and a half
seconds is the real price, and the packet could start as the A comes in rather
than after it lands if that turns out to be too long.

### And the pane's document timeline lags its wall clock

A whole diagnosis was spent on fades that "never ran": `setInterval` and
`performance.now()` advance on the wall clock while the preview pane's document
timeline only advances as it paints, so a WAAPI animation created at t=0 was
still in its delay phase when the wall clock said it should have finished --
and the `setTimeout` that cancels it fired on time. Anything timed against
`performance.now()` in that pane is measuring two different clocks. Pause the
animations and step `currentTime`, including the ones OUTSIDE the layer.

## Every video link in one place, and it owns none of them (12 Sep, fifty-seventh pass)

"For Korean, add a general 'videos' sub-tab where all the video links uploaded
in grammar and stuff will be added to that tab, with the YouTube type embed.
Sortable like the way we sort other things on the site."

A fifth sub-tab under Korean, after Notebook.

### It owns no data, and that is the whole design

There is no videos table and nothing is added here. A video is a LINK that
already lives somewhere -- on a grammar point's resources, on an article, a
certification or an application -- and this tab is a second way of reading
those. So nothing can drift out of step with them, deleting the link where it
was added is what removes it here, and no migration was needed.

**It scans every field in the app a link can be typed into**, not only the
grammar resources it was asked for. That costs nothing, because a link that is
not a video never gets past `ytVideoId` -- and missing one would mean a video
somebody added and cannot find. Measured against a mixed set: five videos came
back from three different sources and the two plain links (an `example.com`
article, a lesson-notes page on a grammar point) were correctly not among them.
Books are the one list with no link field at all, so there is nothing to scan.

### The id is matched against youtube's own FORMS, not parsed as a URL

A link pasted without a scheme is not a valid URL and is exactly what somebody
pastes, so `new URL()` is no use. One regex over the forms youtube publishes
with the id LAST, and **the 11 characters are youtube's own fixed id length** --
which is also what stops it matching a word that happens to follow a slash.
14 of 14 cases: `watch?v=`, `youtu.be/`, a `list=` before the `v=`, `shorts/`,
`m.youtube.com`, `embed/`, `live/`, and `#t=45s`; and null for `example.com/
watch?v=...`, vimeo, a plain page, an empty string and an id of the wrong
length.

**A timestamp on the link is kept.** `?t=90`, `&t=1h2m3s` (3723) and `#t=45s`
all parse, and the embed carries `start=` -- throwing it away would land the
reader at the beginning of an hour-long lecture.

### Nothing loads from youtube until somebody asks

A card is a POSTER and a play button; pressing it swaps in the player. Two
dozen of these would otherwise be two dozen third-party iframes on a tab
somebody opened to browse. The player is `youtube-nocookie.com`, which is the
same player on the host that sets no cookies of its own until something plays.

- **Which cards are playing is held OUTSIDE the markup**, keyed by the video's
  own source and id, so a re-render -- a sort, a keystroke in the search box --
  cannot tear a playing iframe out. Verified: play, re-render, still one
  iframe, same src.
- **The stage keeps its 16:9 whichever is in it** (measured 287x161 = 1.78 on a
  phone), so pressing play cannot move the grid.
- The poster is 4:3 art cropped to a 16:9 stage, which is what youtube's own
  player does with it; `object-fit: cover` is what stops it being stretched.
- `ICON.play` is the one SOLID mark in that set, and it has to be: it sits on a
  photograph, where a stroked outline has nothing to separate it from whatever
  is behind it.

### Sorted with the app's own control

`sortControlHtml` / `wireSortControl` / `saveListSort`, exactly as jobs, certs,
the job board and the expenses do, so multiple sort and the remembered ordering
come for free. Fields are **added, title, source**.

- **A video with NO date sorts LAST whichever way the level is pointed**, the
  same sentinel the job board uses for a listing with no deadline: "undated" is
  not "the oldest".
- **Which is why a grammar resource now records `added` and `by`.** It never
  did, so there was nothing to sort or credit by; from now on it does, and a
  resource added before this is simply undated and uncredited there. Nothing
  had to change in the table -- `resources` is jsonb and `avatarFrom`-style
  field-by-field reading means an extra key costs nothing.
- **The render owns its own control** (`renderVideoList` calls
  `rebuildVideoSortSelect`), the way `renderJobs` does, so the commit has one
  thing to call and the control can never be drawn for an ordering the list is
  not in.

Checked: title ascending gives 3.-거든요, Billie, How Korean…, Talk To Me…,
TOPIK II; source ascending gives Articles, Certifications, Grammar x3; "added"
descending puts 12/09 before 11/09 before 10/09 with the undated one last.
Search filters on the label, the pattern, the source and the URL. Both empty
states say which of the two they are.

### And the plumbing it had to be registered in

`studySubVideosBtn` + `studyVideosSection`, `switchStudySubTab`, `STATIC_MAP`
(four ids), `TAB_STRUCTURE`'s `study.videos` -- which is what the split view
and the nav flyout read, so neither had to learn about it separately --
`renderAll`, `redrawSortControls`, and en/ko/vi. Measured on a phone: five
sub-tab buttons at 63px in a 335px row, nothing clipped and no overflow.

**A harness note worth keeping**: this app's top-level lists are `let`
bindings, so `window.allArticles = ...` from the console creates a SECOND
binding and the app goes on reading the real one. A fake that appears to do
nothing is that, not a bug in the reader -- assign the bare name.

## The offer response was never saved, because the column was never added (12 Sep, fifty-eighth pass)

"I noticed when I edit the job offers to be accepted/rejected etc., it never
saves. Every time I come back, it just says pending again."

**`job_applications.offer_response` did not exist in the live database.** Its
migration (`sql migrations/job_offer_response_migration.sql`) was written and
never run, so every accept/decline was a PostgREST 400 (`42703: column
job_applications.offer_response does not exist`) -- and nothing looked at it.

Proved before changing anything, with the app's own anon key, which is the
cheapest possible check: `GET /rest/v1/job_applications?select=offer_response`
returns that error while `?select=status` returns `[]`. **A column probe
through the REST API needs no session and is unambiguous**: a missing column is
a 400 where an RLS-empty result is a 200 and `[]`.

**Applied to the live database on 12 Sep** (project kbqwitmxpmkueryjsyip,
"Korean"), and checked after: the column is there, nullable, readable through
the API the app uses, and its check constraint is live (probed inside a rolled-
back block, leaving nothing behind).

- **The grants did NOT need touching, and that was checked rather than
  assumed.** This file records for the sibling project that a column added
  after a grant with an explicit column list is not covered by it, and
  `information_schema.column_privileges` looks exactly like that here -- 12
  rows per grantee. It is not: `pg_class.relacl` shows the grants are
  TABLE-level (`authenticated=arwdDxtm`) and **zero columns have their own
  ACL**, so a new column is covered by construction. Read `relacl` and
  `pg_attribute.attacl`, not the information_schema view, which reports a
  table-level grant per column and cannot tell the two apart.
- RLS was already right: `job_applications_update` is `auth.uid() = user_id`
  both ways.

### The code bug is that a refused write looked like a successful one

That is the part worth fixing, because it is what let this sit there. Every
status picker in the app writes, then updates its own copy of the row, then
re-renders -- and **ignores the error**. So a refused write leaves the new
value on screen and the old one in the database, and the first anybody hears of
it is the next load reading back what was there before. Which is exactly the
report, word for word.

`saved(query, onFail)` asks for the result, and **`onFail` is the half that
matters**: it puts the row back. A message on its own would still leave a value
on screen that the database does not have. Applied to the four pickers where
"I changed it and it didn't stick" is the same complaint -- job status, job
offer response, certification status, course status.

**There are 25 more updates in this file whose error is still dropped** (book
and article patches and notes, event locations, the note autosaves, the
sort-order swaps). They are not all the same shape -- several have their own
saving indicator and would want a different answer than an alert -- so they are
written down here rather than swept quietly. `saved()` is the thing to reach
for.

## The cap is what says which way he is looking, and the A bounces off the wall (12 Sep, fifty-eighth pass)

"You are literally pointing the A the wrong way... It's not difficult to make a
2D figure look around and be peeking. Literally just make his head one way (he
is wearing a cap so....) and then his head the other way (cap literally just
faces the other way...?) and then crack his neck so he is looking STRAIGHT
UPWARDS... Make the A bounce off the west side of the window."

### The derived funnel angle was the mistake

Last pass DERIVED the tilt from where the form's fields sit, and that is what
got it wrong: on a wide form the fields wrap across rows ABOVE the button, so
their centroid lands to the RIGHT of his hand and the rule tilted the mouth
up-LEFT. **`AC_A_FUNNEL` is a constant, 225.** Settled by rendering an A at
135, 180, 225 and 270 at 86px and looking: 135 is mouth up-left, 180 straight
up, **225 up-right**, 270 right. Confirmed in the finished animation -- the
collect pose measures 225 and the mouth reads up-right at 6x.

**The lesson is about the derivation, not the number.** A rule that computes
something the eye can check is worth having only if it is checked against the
eye; this one was reasoned from "the pills come from the fields" and never
looked at.

### A flat silhouette turns by MIRRORING, and the cap is the only part that can

Third report on the same four seconds, and the answer was in the report: "he is
wearing a cap so...". A rotation about the neck is a head TIPPING, whatever
size it is drawn -- which is why two passes of it read as throwing his head
back. What a flat drawing has instead of a three-quarter view is a mirror.

- **The peak is its own group**, because it is the only asymmetric thing on the
  head: the skull is a circle, and the cap's crown and its brim line are both
  symmetric about the centre line. So mirroring the PEAK alone turns the head
  round, where mirroring the whole group would squash the skull to a line on
  the way through `scaleX(0)`.
- **It flips DURING each move rather than at a hold**, so what the eye sees is
  the peak narrowing as the head swings and opening out on the other side --
  the same cosine the header's globe turns on.
- **Looking straight up is a quarter turn about the SKULL'S OWN CENTRE**, not
  the neck. About the neck a 90-degree turn swings the whole head out sideways
  like a ball on a stick (the head circle's centre moves from 4.3 above the
  neck to 4.3 beside it); about the skull's own centre the circle does not move
  at all and only the cap does, which is the whole of what says which way he is
  facing. `.ac-head`'s origin moved from `15px 12px` to `15px 7.7px`, and the
  springy curve into it is the crack.
- Measured at the beats: peak LEFT of the head (576 against a head at 581),
  then RIGHT of it (594 against 590) with `scaleX(-1)`, then rotated **90
  degrees** with the peak un-flipped and centred over the head -- pointing at
  the ceiling.

### The throw bounces off the west wall

`AC_T.back` is 2200 and the path is: in from off-screen east, across the whole
window, onto the left edge, and back to the button.

- **Every number is measured off the window and the letter's own glyph box**,
  so it is the same throw at any width. Verified at 1024 and at 375: the
  letter's left edge reaches **2px** from the window's edge in both, and it
  lands back on the label to the pixel.
- **The pad is the letter's half-DIAGONAL, not its half-width.** The first
  version used the width and the ink crossed the edge by 2px while the letter
  was turned 45 degrees; the diagonal is the bound at any rotation.
- **The spin REVERSES at the wall**, which is most of what says it bounced
  rather than curved: backwards on the way out (365 to 245) and forwards on the
  way home, landing on a whole number of turns so the pose it lands in is the
  pose the button draws (measured: 5, 283, 252, 245 at the wall, then 302, 341,
  0).
- **The beat is placed by DISTANCE, not at a fixed offset.** The two legs are
  very different lengths -- about 1050px out and 570 back on a desktop -- so a
  fixed 0.5 would run the short leg home at half the pace of the long one out.
- **The arc is capped against the top of the window** rather than being a fixed
  height, or an Add button near the top would throw the letter off the screen.
- **A window too narrow to get properly west of the button flies straight in
  as before.** On a phone the Add button really can sit a thumb's width from
  the left edge, and 30px of westward travel is a wobble rather than a bounce.

### Checked, and the cost

One real-timer run end to end: no layer left, the label back as one text node,
`acBusy` and `acRevealing` both false, the deferred row rendered exactly once,
and **no animation left on any field** with all three inks back to full.

The whole run is now **5.84s to the landing and 6.3s to the row**. That is the
price of the 2200ms bounce, and it is worth saying plainly: the row not
appearing for six seconds is the one part of this nobody asked for, and the
packet could leave as the A passes the wall rather than after it lands.

## One speed the whole way, a row that really waits, and a packet out of the A (12 Sep, fifty-ninth pass)

"The A flies through the air SOOOO FUCKING FAST and then it falls down SO
FUCKING SLOW. The whole animation should be sort of the same speed, of course
hitting the wall will make it slow down a bit... the row DOES SHOW UP VISUALLY
ALMOST RIGHT AWAY, so that's a fucking failure in that department... it does not
look like it's the A (as it hits the ground) that is firing it out to the
position it should be in. Let the box and text fly out of it and land."

### The throw is a SPEED now, and every leg is timed by its own length

Two faults, and the second is the one that made it read as two different
animations:

- **A fixed duration over a path whose length depends on the window** means
  the letter races across a desktop and crawls across a phone. `AC_A_SPEED` is
  400 px/s and the duration is worked out from the path. 400 is bracketed by
  what has already been rejected: 540 px/s was "way too fast", **734 was what
  the bounce shipped at**, and 318 was accepted.
- **The path was timed as ONE eased block.** A decelerating curve over a
  1075px leg spends most of its distance in the first third, so the run west
  was a blur and the arc home a crawl. It is a POLYLINE timed by ARC LENGTH
  now: every segment gets time in proportion to how far it actually goes, and
  every segment is `linear`.

**A LEG THAT CHANGES SPEED NEEDS MORE TIME THAN ITS LENGTH BUYS.** That is not
a taste call, it is arithmetic, and it cost a whole attempt: a leg's average
speed is its length over its time, so one that enters at the run's pace and
then slows must average LESS than that pace -- which it cannot do on a share of
the clock worked out from its length alone. Given exactly its share, the only
way to arrive on time is to speed up first, which is precisely what it drew: a
settle that ran to **507 px/s** before stopping dead, in the middle of an
otherwise flat 400. So the brake, the kick and the settle are STRETCHED (1.5,
1.5, 1.7) and their curves are written to OPEN at that stretch -- a
cubic-bezier's initial slope is `y1/x1`, so `y1/x1 == stretch` means "carry on
at the pace you arrived at" and everything after it is the slowing down.

Measured at 100ms over the whole flight, and this is the whole test:

    400 x25   355 263 27   247 342   400 x10   393 265 86
    <-- run west -->  <- wall ->  <- away ->  <- arc home ->  <- settle ->

**`max` is 400** -- the letter never exceeds the run's own pace anywhere on the
path. The only deviation is the wall, which is what was asked for.

- **The easing on a keyframe governs the segment STARTING there**, and getting
  that wrong put the kick a whole leg late: a front-loaded curve landed on the
  arc home and sprinted it at 566 px/s. Only an INSERTED node carries a curve.
- The brake and the settle are DISTANCES (66px, 58px), so the impact is the
  same event on a phone as on a desktop.

### The row was being shown by the realtime subscription, not by the courier

"Almost right away" was about 600ms, and it was this: **the app subscribes to
`postgres_changes` on `job_applications`, `books`, `certifications`, `courses`,
`study_entries` and `events`**, so an insert echoes back to the tab that made
it and `scheduleSharedDataRefresh` renders the whole app 600ms later. The
courier was holding its own render and something else was doing it anyway.

**The reveal is a QUEUE, not one slot**, and the refresh joins it -- the DATA
is still always re-read, only the render waits, and only while a courier is
out. Deduped by function identity, so a burst of echoes queues one `renderAll`
rather than a dozen, and a later caller that names a target upgrades the
queued entry rather than replacing it. One slot was the same leak by another
road: the second caller flushed the first.

Measured: with a courier out, the handler's own render and three background
echoes all queue (two entries after dedupe), the packet's target is still the
list the handler named, and both run exactly once on delivery. And with real
timers, two echoes fired at 700ms and 1600ms and **the row rendered once, at
8833ms.**

### The packet comes out of the A, and carries what was typed

It started at the button's centre at an arbitrary 0.12 scale, which read as the
button producing it. Now it starts **exactly on the landed glyph** -- measured,
the packet's first frame is cx 548, cy 139, h 17 against a glyph at cx 548, cy
139, h 17, and at opacity 0, so it emerges rather than appears -- and grows to
the row's size as it flies (170x17 to 340x34).

- **It carries the field values**, which is what makes it read as the row
  rather than a parcel: the same text the pills brought IN.
- **A date or a quantity is not what a row is CALLED**, so the headline is the
  first field that is neither -- the company on an application, the title on a
  book, the activity on a study session. Without that rule the packet arrived
  announcing "2026-09-12".
- **The A kicks as it goes**, on the button's own glyph (which by then is what
  is on screen), so the letter is visibly what fired it. `gSpan` is
  `inline-block` for that; one character either way, so its baseline and width
  are unchanged.
- Its own duration comes from `AC_A_SPEED` too, floored at 340ms so a short hop
  is still a throw and capped at `AC_T.deliver` so the cleanup timer, which is
  set before the distance is known, is always long enough.

### Checked, and the cost

One real-timer run end to end: nothing left behind (0 layers, 0 packets), the
label back as one text node, `acBusy` and `acRevealing` false, the queue empty,
no animation left on any field, all three inks restored, the form cleared and
no transform left on the button.

**Press to row is now 8.8s**, from 6.3s. That is the arithmetic of the two
things asked for together: the path is the window's width plus the way back
(~1550px on a desktop) and the pace is 400 px/s, so the throw alone is 4.3s.
Getting back to 6s means ~670 px/s, which is the speed that was just rejected.
Worth saying rather than quietly splitting the difference.
