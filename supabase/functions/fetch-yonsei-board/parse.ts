// Parser for the public Yonsei GSIS "Official Notices" board.
//
// Kept in its own dependency-free module (no Deno APIs, no imports) so it can
// be unit-tested against a saved copy of the board HTML outside the edge
// runtime. index.ts does the fetching and serving; this file only turns the
// page's HTML into structured items.
//
// The board renders one <tr> per notice. Pinned rows carry the extra class
// c-board-top-wrap, but their inner markup is identical to regular rows, so
// both are parsed by the same pass. The shape we rely on is:
//
//   <div class="c-board-title-wrap">
//     <a href="?mode=view&articleNo=476279&..." class="c-board-title">
//       <span class="c-board-top-num-m">[공지]</span>   (pinned rows only)
//       [Recruiting]
//       ODAR Assistant
//     </a>
//     <div class="c-board-info-m">
//       <span>국제학대학원</span>
//       <span>2026.08.10</span>
//     </div>
//   </div>
//
// Only the anchor (link + title) and the date that follows it are used. If
// Yonsei changes the board layout, this is the file to retune.

// category is always one of the canonical buckets below (never the raw
// bracket text, and never null) -- untagged notices and unrecognized tags
// both fall back to "General Notice" rather than going uncategorized, so
// every item is always filterable/notifiable by category. subTag is the
// second bracket some Academics notices carry right after the category
// (e.g. "[Academics] [GCC] ...", a course-code marker), kept raw/uncanon-
// icalized since it's just used as an opaque hide/show key, not displayed
// as a colored badge the way category is.
export type BoardItem = {
  title: string;
  link: string;
  date: string;
  category: string;
  subTag: string | null;
};

export const YONSEI_BOARD_CATEGORIES = [
  "Academics",
  "Recruiting",
  "Admission",
  "Event",
  "General Notice",
] as const;

export const YONSEI_BOARD_URL =
  "https://gsis.yonsei.ac.kr/gsis/community/boards1_01.do";
const YONSEI_ORIGIN = "https://gsis.yonsei.ac.kr";

// Anchor for one notice. Matched loosely on attribute order so an added
// attribute (target, title, data-*) does not break the match.
const ANCHOR_RE =
  /<a\b[^>]*href="([^"]*mode=view[^"]*)"[^>]*class="[^"]*c-board-title[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
// The "[공지]" badge that prefixes pinned titles. Dropped from the title
// text; the category tag that follows it ("[Recruiting]", "[Admission]") is
// plain text inside the anchor and is deliberately kept.
const PINNED_BADGE_RE =
  /<span\b[^>]*class="[^"]*c-board-top-num-m[^"]*"[^>]*>[\s\S]*?<\/span>/gi;
const TAG_RE = /<[^>]+>/g;
// Full date from the c-board-info-m block that follows the anchor.
const DATE_FULL_RE = /<span\b[^>]*>\s*(\d{4})\.(\d{2})\.(\d{2})\s*<\/span>/;
// Fallback: the plain YY.MM.DD cell further along the same row.
const DATE_SHORT_RE = /\b\d{2}\.\d{2}\.\d{2}\b/;
// How far past the anchor to look for that date, in characters. One row's
// remaining markup is well under this.
const DATE_LOOKAHEAD = 600;

const NAMED_ENTITIES: Record<string, string> = {
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
  "&apos;": "'",
  "&nbsp;": " ",
};

// &amp; is decoded last so that an escaped entity in the source ("&amp;lt;")
// survives as literal text ("&lt;") instead of being decoded twice.
function decodeEntities(s: string): string {
  return s
    .replace(/&(?:lt|gt|quot|apos|nbsp|#39);/gi, (m) => NAMED_ENTITIES[m.toLowerCase()] ?? m)
    .replace(/&#(\d+);/g, (_, d) => {
      const code = Number(d);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    })
    .replace(/&amp;/gi, "&");
}

// Board hrefs are relative query strings ("?mode=view&articleNo=..."), so
// they only resolve against the board URL, not against the function's origin.
function absolutize(href: string): string {
  if (/^https?:\/\//i.test(href)) return href;
  if (href.startsWith("?")) return YONSEI_BOARD_URL + href;
  if (href.startsWith("/")) return YONSEI_ORIGIN + href;
  return YONSEI_BOARD_URL + "?" + href.replace(/^[?&]/, "");
}

function cleanTitle(innerHtml: string): string {
  const text = innerHtml.replace(PINNED_BADGE_RE, " ").replace(TAG_RE, " ");
  return decodeEntities(text).replace(/\s+/g, " ").trim();
}

const LEADING_BRACKET_RE = /^\[([^\]]+)\]\s*/;

// Raw bracket text -> canonical category. "[Current]" (seen on Dean's
// Scholarship/financial-aid notices) reads as an academics-adjacent status
// marker, not its own category, so it's folded into Academics. Anything not
// matched here -- an untagged notice, or a future tag Yonsei starts using --
// falls back to "General Notice" rather than left uncategorized.
function canonicalCategory(raw: string | null): string {
  if (!raw) return "General Notice";
  const c = raw.toLowerCase();
  if (/recruit/.test(c)) return "Recruiting";
  if (/academic/.test(c) || /current/.test(c)) return "Academics";
  if (/admission/.test(c)) return "Admission";
  if (/event/.test(c)) return "Event";
  return "General Notice";
}

// Only these second-bracket values are real course-code markers worth
// surfacing as a filterable sub-tag. Everything else seen in that position
// -- "RA Recruitment"/"ODAR"/"Recruiting" (redundant with the Recruiting
// category itself), "CALL FOR PAPERS"/"Announcement"/"Event", one-off
// hirer names ("NOVAsia Magazine is Hiring", "UIC Recruiting"), and a long
// tail of post-specific "updated as of <date>" stamps -- is noise that used
// to flood the sub-tag filter list with entries nobody would ever want to
// filter by. Case-insensitive match; the original casing is kept as the
// displayed/stored value so it lines up with subtags already saved in
// profiles.yonsei_hidden_subtags.
const SUBTAG_ALLOWLIST = new Set(["GCC", "GCSD"]);

// Splits a cleaned title into { category, subTag, title }: the leading
// "[Category]" bracket (if any) becomes the canonical category, a second
// leading bracket right after it (if any) becomes subTag only when it's one
// of SUBTAG_ALLOWLIST's real course-code markers. When it isn't (the common
// case), that bracket's text is folded back into the title instead of being
// discarded -- e.g. "[Academics] [YJIS - CALL FOR PAPERS]" has nothing else
// to show, so dropping the second bracket unconditionally (the old
// behavior) left the title blank.
function splitYonseiTitle(cleaned: string): { category: string; subTag: string | null; title: string } {
  const m1 = cleaned.match(LEADING_BRACKET_RE);
  if (!m1) return { category: canonicalCategory(null), subTag: null, title: cleaned };
  const rest1 = cleaned.slice(m1[0].length);
  const m2 = rest1.match(LEADING_BRACKET_RE);
  if (!m2) return { category: canonicalCategory(m1[1].trim()), subTag: null, title: rest1 };
  const rawSubTag = m2[1].trim();
  const remainder = rest1.slice(m2[0].length);
  if (SUBTAG_ALLOWLIST.has(rawSubTag.toUpperCase())) {
    return { category: canonicalCategory(m1[1].trim()), subTag: rawSubTag, title: remainder };
  }
  return {
    category: canonicalCategory(m1[1].trim()),
    subTag: null,
    title: remainder ? `${rawSubTag} ${remainder}` : rawSubTag,
  };
}

// Dates are normalised to YY.MM.DD, matching what the board's own list column
// shows and what the app rendered before this parser existed.
function dateAfter(html: string, from: number): string {
  const window = html.slice(from, from + DATE_LOOKAHEAD);
  const full = window.match(DATE_FULL_RE);
  if (full) return `${full[1].slice(2)}.${full[2]}.${full[3]}`;
  const short = window.match(DATE_SHORT_RE);
  return short ? short[0] : "";
}

// Yonsei's own list order pins certain notices (recruiting posts, etc.) to
// the top regardless of date, mixed in with the rest in reverse-chronological
// order. We always want newest-first on our side, so the collected items are
// re-sorted by date before being returned; items with an unparsed (empty)
// date are pushed to the end rather than sorted arbitrarily.
function compareDateDesc(a: BoardItem, b: BoardItem): number {
  if (!a.date && !b.date) return 0;
  if (!a.date) return 1;
  if (!b.date) return -1;
  return b.date.localeCompare(a.date);
}

export function parseYonseiBoardHtml(html: string, maxItems = 1000): BoardItem[] {
  const items: BoardItem[] = [];
  const seen = new Set<string>();
  ANCHOR_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = ANCHOR_RE.exec(html)) !== null) {
    const link = absolutize(decodeEntities(m[1]));
    const articleNo = link.match(/articleNo=(\d+)/);
    const key = articleNo ? articleNo[1] : link;
    if (seen.has(key)) continue;
    const cleaned = cleanTitle(m[2]);
    if (!cleaned) continue;
    seen.add(key);
    const { category, subTag, title } = splitYonseiTitle(cleaned);
    items.push({ title, link, date: dateAfter(html, ANCHOR_RE.lastIndex), category, subTag });
    if (items.length >= maxItems) break;
  }
  return items.sort(compareDateDesc);
}
