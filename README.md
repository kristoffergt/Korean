# Productivity Tracker

A shared study and productivity tracker, live at **[kristoffergt.com](https://kristoffergt.com)**.

It started as a Korean-study companion for two people to track progress side by side, and grew into a general productivity tracker that anyone can sign up for and use on their own — or link up with specific people to share progress with, the same way the two original users do.

It's a single self-contained HTML file (`korean_study_tracker.html`) — no build step, no framework, no server code beyond [Supabase](https://supabase.com) for the database, auth, and file storage. Deployed as a static site via GitHub Pages.

## Features

**Calendar** — month/week/day views, deadlines and custom events, a TOPIK exam countdown, a weekly/monthly recap of activity, and a per-tab "who's events show" filter for picking specific people out of your linked circle.

**Study** — four sub-tabs:
- *Log* — a study session timer and daily/weekly logging, streaks, and a personal daily goal.
- *Grammar* — a full Korean grammar reference with formation notes, examples, colloquial/written usage, similar-grammar comparison tables, favoriting, and a multiple-choice quiz with SM-2 spaced repetition (patterns you get wrong resurface sooner).
- *Writing* — TOPIK writing practice (Q53 data-description and Q54 essay tasks), a combined 50-minute mock exam mode with side-by-side timed editors, shareable writing samples, and a comment thread for feedback on each sample.
- *Notebook* — freeform personal notes.

**Courses** — a weekly course schedule with day/time slots, professor, syllabus upload, midterm/final dates, an optional TA/RA flag per course (set when adding or editing a course), and a lock-in flow once you've committed to a course.

**Notes** — per-course lecture notes, plus a general notes section with custom headers.

**Reading** — a book log (currently reading / finished, with notes and page tracking) and a public reading leaderboard.

**Jobs** — a job application tracker (company, role, status, date applied, link), editable after the fact, paginated (3 shown, expanding to 10-per-page), a paste-to-autofill that parses a copy-pasted summary straight into the form, and a public leaderboard.

**Accounts & privacy** — email/password auth with optional 2FA, per-user display colors, a "hide me from leaderboards" toggle, account deletion, and a moderator/admin panel. The two original users share everything with each other by default and always will; everyone else's data is private by default unless they opt into linking with up to 10 other people and choosing, per category (study log, books, jobs, grammar notes, course notes, writing samples, recap, readiness), what they share and with whom — including per-person overrides.

**Everything else** — English/Korean/Vietnamese interface, light and dark mode, and a mobile-responsive layout.

## Tech

- Single HTML file: markup, CSS, and JavaScript all in one place.
- [Supabase](https://supabase.com) for Postgres (with row-level security), auth, and storage.
- SQL migrations live in `sql migrations/`.
- Hosted on GitHub Pages.
