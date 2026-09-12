# Productivity Tracker

A shared study and productivity tracker, live at **[kristoffergt.com](https://kristoffergt.com)**.

It started as a Korean-study companion for two people to track progress side by side, and grew into a general productivity tracker: a place to keep a study log, a degree, a job hunt, a reading list and a shared budget in one account, on your own or linked up with specific people to share progress with.

It's a single self-contained HTML file (`index.html`, named for GitHub Pages), no build step, no framework, no bundler, no server code of its own beyond [Supabase](https://supabase.com) for the database, auth and file storage, plus a handful of Deno edge functions for the things that have to run on a schedule. Deployed as a static site via GitHub Pages.

Signing up needs a 4-digit **site PIN**, so the instance is invite-only in practice rather than open to the web.

## Features

### Home
- **Overview** – the leaderboard, the activity feed, a per-activity breakdown, a twelve-week heatmap, a study-session timer and daily logging with streaks and a personal daily goal.
- **Calendar** – month, week and day views, deadlines and custom events, recurring events, per-event reminders, a TOPIK exam countdown, and a weekly/monthly recap of activity. A "whose events show" filter picks specific people out of your linked circle, and the whole calendar can be downloaded as a picture or exported as `.ics`.
- **Expenses** – shared trip budgets. A vacation with its own dates and currency, members invited from your linked circle, expenses by category and payer, **balances** showing who owes whom, averages per day and per week, multi-currency with optional conversion of every amount, and per-expense, per-day and per-category exclusions for things that shouldn't count.

### Korean
- **Log** – study sessions by activity, logged by hand or from the timer.
- **Grammar** – a full Korean grammar reference with formation notes, examples, difficulty/formality/politeness/register bars, similar-grammar comparison tables, favouriting, your own example sentences checked against the pattern, per-pattern resource links, and a multiple-choice quiz with SM-2 spaced repetition so patterns you get wrong resurface sooner.
- **Writing** – TOPIK writing practice (Q53 data description, Q54 essay), a combined 50-minute mock exam with side-by-side timed editors, image attachments, version history, shareable samples and a comment thread for feedback on each.
- **Notebook** – freeform personal notes, grouped under your own headers.
- **Videos** – every video link added anywhere in the app, gathered in one place with YouTube embeds, searchable and sortable.

### Yonsei
- **Courses** – a weekly schedule with day/time slots, professor, classroom, syllabus upload, midterm/final dates, concentration, an optional TA/RA flag, and a lock-in flow once you've committed. Courses can be shared, and each one puts its own dates on the calendar.
- **Notes** – per-course lecture notes with pages, colours and live "someone is writing" indicators.
- **Board** – Yonsei GSIS official notices, fetched on a schedule, searchable and filterable, with opt-in notifications when new ones land.

### Reading
- **Books** – currently reading / to read / finished, with notes and page tracking, and a public leaderboard.
- **Articles** – the same for articles, with source and link.

### Jobs
- **Applications** – company, role, status, date applied, link, and CV/cover-letter PDF uploads, editable after the fact, searchable, sortable and paginated. A paste-to-autofill parses a copy-pasted summary straight into the form. Offers can be marked accepted or declined. Public leaderboard.
- **Certifications** – name, issuer, status, completion date and link.
- **Board** – Yonsei GSIS job and internship postings, ingested on a schedule, with industry and type filters, deadlines, and a sort.

### Throughout
- **Uploaded files get short links** – every CV, cover letter and syllabus gets a `kristoffergt.com/f/<slug>` you can rename, and deleting the row it belongs to takes the file and the link with it.
- **Multi-level sorting** – the lists share one sort control: pick one field, or turn on multiple sort and stack several, and the choice is remembered.
- **Notifications** – an in-app bell and optional email for calendar reminders, new Yonsei notices and accepted link invites, plus weekly/monthly recaps.
- **Circle messaging** – direct messages within your linked circle, with attachments, read receipts, typing indicators and presence.
- **Accounts & privacy** – email/password auth with optional 2FA and backup codes, per-user display colours, a "hide me from leaderboards" toggle, account deletion, a support form, and a moderator/admin panel. The two original users share everything with each other by default; everyone else's data is private unless they opt into linking with up to 10 people and choose, per category (study log, books, articles, jobs, certifications, grammar notes, course notes, writing samples, recap, readiness), what they share and with whom, including per-person overrides.
- **Everything else** – English, Korean and Vietnamese, light and dark mode, a mobile-responsive layout, installable as a PWA with an offline app shell, and animations that can be switched off by group (header marks, title, interface motion, the add courier) for anyone who'd rather they weren't there.

## Tech

- **One HTML file**: markup, CSS and JavaScript all in `index.html`. No build, no dependencies to install.
- **[Supabase](https://supabase.com)** for Postgres with row-level security, auth, and storage.
- **Edge functions** in `supabase/functions/` (Deno): fetching and notifying on the Yonsei notice board, ingesting the job board and its detail pages, and a webhook that records when a third-party page monitor sees the GSIS Instagram change.
- **SQL migrations** in `sql migrations/`, applied by hand.
- **Email templates** in `supabase/email-templates/`.
- **Helper scripts** in `scripts/` for the job board sync.
- `sw.js` caches the app shell so a reload survives a flaky connection; the data itself is always fetched live.
- Hosted on GitHub Pages, with a `404.html` that matches the app.

## Working on it

`CLAUDE.md` is the running log: every round of work, what was reported, what
was measured, and the traps that cost time. It is the first thing to read
before changing anything.
