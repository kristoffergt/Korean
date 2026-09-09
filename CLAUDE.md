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
