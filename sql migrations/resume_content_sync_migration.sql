-- ============================================================================
-- Lets the resume page (resume/index.html, public/kristoffergt.com/resume)
-- render from stored data instead of hardcoded HTML, so re-syncing it from
-- an updated version of the same resume doesn't require editing the page's
-- source by hand each time. Single row, admin-only write (same
-- current_is_admin() gate as the resume PDF storage bucket), public read
-- since the resume page itself is unauthenticated.
--
-- Safe to re-run.
-- ============================================================================

create table if not exists resume_content (
  id text primary key default 'main',
  content jsonb not null,
  updated_at timestamptz not null default now()
);

alter table resume_content enable row level security;

drop policy if exists "resume_content public read" on resume_content;
create policy "resume_content public read" on resume_content
  for select
  to anon, authenticated
  using (true);

drop policy if exists "resume_content admin write" on resume_content;
create policy "resume_content admin write" on resume_content
  for all
  to authenticated
  using (current_is_admin())
  with check (current_is_admin());

insert into resume_content (id, content) values ('main', $json${
  "header": {
    "name": "KRISTOFFER GRILLO TIEDEMANN",
    "linkedin": "linkedin.com/in/kristoffer-tiedemann",
    "location": "Seoul, Gwanak-gu, South Korea",
    "phone": "+82 10-2382-5552",
    "email": "kristoffergt@gmail.com"
  },
  "sections": [
    {
      "title": "Education",
      "entries": [
        {
          "title": "Yonsei University, Graduate School of International Studies",
          "location": "Seoul, South Korea",
          "subtitle": "Master of Global Economy & Strategy (MGES); International Trade, Finance & Management",
          "date": "Mar 2025 – Present",
          "bullets": [
            "Dean's List for Academic Excellence, all three completed semesters (GPA 4.17/4.3, Top 1%)",
            "Selected coursework: International Trade, Understanding the Free Trade Agreements, Digital Trade in the Making"
          ]
        },
        {
          "title": "Aarhus University, School of Business and Social Sciences",
          "location": "Aarhus, Denmark",
          "subtitle": "BSc in Economics & Business Administration; Ø GPA 10.0/12.0 (Top 10%)",
          "date": "Aug 2020 – Sep 2023",
          "bullets": [
            "Selected coursework: Industrial Organisation & Strategy, Marketing Management, Business Intelligence & Data Mining"
          ]
        },
        {
          "title": "Korea University Business School",
          "location": "Seoul, South Korea",
          "subtitle": "Exchange semester (5th semester of BSc); Ø GPA 4.13/4.5",
          "date": "Sep 2022 – Feb 2023",
          "bullets": []
        }
      ]
    },
    {
      "title": "Projects & Research",
      "entries": [
        {
          "title": "Bachelor's Thesis – The Success of Venture Capital Backed Startups During a Recession",
          "location": "Aarhus, Denmark",
          "subtitle": null,
          "date": "2023",
          "bullets": [
            "Built a dataset of ~39,000 US venture-backed companies from Crunchbase and Dealroom, most of it spent collecting and cleaning records from messy commercial sources",
            "Logistic regression on survival and multiple regression on eventual valuations, in JMP"
          ]
        },
        {
          "title": "DILEMMA 2026 – Scenario Designer & Co-Moderator, Yonsei University (NATO-funded)",
          "location": "Seoul, South Korea",
          "subtitle": null,
          "date": "2026 – Present",
          "bullets": [
            "Designing scenario architecture and co-moderating a multinational exercise with university teams from six countries",
            "Writing the country profiles, market briefings, and crisis injects the competing teams work from"
          ]
        },
        {
          "title": "Research – Co-Author, Yonsei Journal of International Studies",
          "location": "Seoul, South Korea",
          "subtitle": null,
          "date": "2025 – Present",
          "bullets": [
            "Cross-border Artificial Intelligence Services and the WTO's Eroding Legal Framework – Revised and resubmitted following peer review"
          ]
        },
        {
          "title": "welcomekorea.org – Designer & Developer",
          "location": "Seoul, South Korea",
          "subtitle": null,
          "date": "2026",
          "bullets": [
            "Built and deployed a trip-planning web app for Korea in Danish, English, and Korean, shipped solo with AI-assisted development"
          ]
        }
      ]
    },
    {
      "title": "Professional Experience",
      "entries": [
        {
          "title": "Yonsei University GSIS – <em>Teaching Assistant, Intro to International Economics</em>",
          "location": "Seoul, South Korea",
          "subtitle": null,
          "date": "Spring Semester 2026",
          "bullets": [
            "Supported students with course material, exercises, and exam preparation"
          ]
        },
        {
          "title": "365 Discount – <em>Store Operations</em>",
          "location": "Børkop, Denmark",
          "subtitle": null,
          "date": "Aug 2024 – Jan 2025",
          "bullets": [
            "Managed daily opening/closing procedures and ran evening shifts independently"
          ]
        },
        {
          "title": "Rema 1000 – <em>Store Operations & Staff Training</em>",
          "location": "Børkop, Denmark",
          "subtitle": null,
          "date": "May 2015 – Aug 2024",
          "bullets": [
            "Led evening store operations for 9+ years, including opening/closing and staff training"
          ]
        }
      ]
    },
    {
      "title": "Additional Information",
      "info": [
        {"label": "Languages", "value": "Danish (native), English (C2), Korean (TOPIK Level 4), German (B1) & Spanish (A2)"},
        {"label": "Digital", "value": "Microsoft 365 (proficient), JMP (statistical analysis), SAP, R"},
        {"label": "Certificates", "value": "Cambridge CEFR C2, IELTS 8.5, TOPIK Level 4"},
        {"label": "Interests", "value": "Hiking, Traveling, AI-Assisted Development, Hybrid/Modern Warfare, Geopolitics"}
      ]
    }
  ]
}$json$::jsonb)
on conflict (id) do nothing;
