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
