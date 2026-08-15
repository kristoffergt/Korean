// Parser for the public Yonsei GSIS "Official Notices" board.
//
// Byte-for-byte copy of ../fetch-yonsei-board/parse.ts. Each Supabase Edge
// Function is deployed as its own self-contained file set, so it can't
// import a sibling function's module at runtime; duplicating this one small,
// dependency-free file is simpler than introducing a shared-module deploy
// step for two call sites. If the board layout changes and this file needs
// retuning, update both copies together.
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

export type BoardItem = { title: string; link: string; date: string };

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

// Dates are normalised to YY.MM.DD, matching what the board's own list column
// shows and what the app rendered before this parser existed.
function dateAfter(html: string, from: number): string {
  const window = html.slice(from, from + DATE_LOOKAHEAD);
  const full = window.match(DATE_FULL_RE);
  if (full) return `${full[1].slice(2)}.${full[2]}.${full[3]}`;
  const short = window.match(DATE_SHORT_RE);
  return short ? short[0] : "";
}

export function parseYonseiBoardHtml(html: string, maxItems = 20): BoardItem[] {
  const items: BoardItem[] = [];
  const seen = new Set<string>();
  ANCHOR_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = ANCHOR_RE.exec(html)) !== null) {
    const link = absolutize(decodeEntities(m[1]));
    const articleNo = link.match(/articleNo=(\d+)/);
    const key = articleNo ? articleNo[1] : link;
    if (seen.has(key)) continue;
    const title = cleanTitle(m[2]);
    if (!title) continue;
    seen.add(key);
    items.push({ title, link, date: dateAfter(html, ANCHOR_RE.lastIndex) });
    if (items.length >= maxItems) break;
  }
  return items;
}
