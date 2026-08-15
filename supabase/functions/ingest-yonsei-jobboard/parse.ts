// Parser for the login-gated Yonsei GSIS CDC "Job/Internship Board"
// (https://gsis1.yonsei.ac.kr/cdc/board.asp?mid=n02_01). Dependency-free
// (no Deno APIs, no imports) so it can be unit-tested outside the edge
// runtime, same convention as fetch-yonsei-board/parse.ts.
//
// The board's table (id="BBSBoard") has one <tr> per listing with columns
// No (a <th>, not a <td> -- excluded automatically by only reading <td>
// cells), Date, Industry, Type, Title (an <a> plus a decorative "new" icon
// image right after it), Deadline, Read. Only Date/Industry/Type/Title/
// Deadline are kept -- No and Read were explicitly not wanted.
//
// idx is pulled from the listing link's "idx=" query param and used as a
// stable id for upserting (see yonsei_jobboard_migration.sql).
//
// Dates render as "Aug 14, 2026" (deadline is the same format or "-" for
// none). Parsed against a fixed month-name table rather than new Date(...):
// testing this against a real saved copy of the page showed new Date(...)
// + toISOString() silently shifts the date by a day depending on the host's
// timezone, so this avoids Date/timezone handling entirely.
export type JobBoardItem = {
  idx: number;
  link: string;
  title: string;
  industry: string;
  type: string;
  datePosted: string; // YYYY-MM-DD
  deadline: string | null; // YYYY-MM-DD or null ("-" on the site)
};

const TBODY_RE = /<tbody>([\s\S]*?)<\/tbody>/;
const ROW_RE = /<tr[^>]*>([\s\S]*?)<\/tr>/g;
const CELL_RE = /<td[^>]*>([\s\S]*?)<\/td>/g;
const LINK_RE = /<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/;
const TAG_RE = /<[^>]+>/g;

const NAMED_ENTITIES: Record<string, string> = {
  "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
};
function decodeEntities(s: string): string {
  return s
    .replace(/&(?:lt|gt|quot|apos|nbsp|#39);/gi, (m) => NAMED_ENTITIES[m.toLowerCase()] ?? m)
    .replace(/&#(\d+);/g, (_, d) => {
      const code = Number(d);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    })
    .replace(/&amp;/gi, "&");
}
function cleanText(html: string): string {
  return decodeEntities(html.replace(TAG_RE, " ")).replace(/\s+/g, " ").trim();
}

// Board dates render as "Aug 14, 2026" / deadlines as either the same format
// or "-" for none. Parsed by hand against a fixed month table rather than
// new Date(...): the runtime's local-time interpretation of a bare
// "Mon DD, YYYY" string combined with toISOString()'s UTC conversion can
// silently shift the date by a day depending on the host's timezone (caught
// this in testing -- Aug 14 came out as Aug 13 locally), so this avoids
// Date/timezone handling entirely and just formats the three parsed numbers
// straight into an ISO string.
const MONTHS: Record<string, string> = {
  jan: "01", feb: "02", mar: "03", apr: "04", may: "05", jun: "06",
  jul: "07", aug: "08", sep: "09", oct: "10", nov: "11", dec: "12",
};
const BOARD_DATE_RE = /^([A-Za-z]{3})\w*\s+(\d{1,2}),\s*(\d{4})$/;
function parseBoardDate(text: string): string | null {
  const t = text.trim();
  if (!t || t === "-") return null;
  const m = t.match(BOARD_DATE_RE);
  if (!m) return null;
  const month = MONTHS[m[1].toLowerCase()];
  if (!month) return null;
  return `${m[3]}-${month}-${m[2].padStart(2, "0")}`;
}

export function parseYonseiJobBoardHtml(html: string): JobBoardItem[] {
  const tbodyMatch = html.match(TBODY_RE);
  if (!tbodyMatch) return [];
  const items: JobBoardItem[] = [];
  const seen = new Set<number>();
  let rowMatch: RegExpExecArray | null;
  ROW_RE.lastIndex = 0;
  while ((rowMatch = ROW_RE.exec(tbodyMatch[1])) !== null) {
    const row = rowMatch[1];
    const cells: string[] = [];
    let cellMatch: RegExpExecArray | null;
    CELL_RE.lastIndex = 0;
    while ((cellMatch = CELL_RE.exec(row)) !== null) cells.push(cellMatch[1]);
    // Row shape (the "No" column is a <th>, not a <td>, so it's already
    // excluded): [Date, Industry, Type, Title(<a>...</a> + a "new" icon), Deadline, Read]
    if (cells.length < 5) continue;
    const [dateCell, industryCell, typeCell, titleCell, deadlineCell] = cells;
    const linkMatch = titleCell.match(LINK_RE);
    if (!linkMatch) continue;
    const link = decodeEntities(linkMatch[1]);
    const idxMatch = link.match(/[?&]idx=(\d+)/);
    if (!idxMatch) continue;
    const idx = Number(idxMatch[1]);
    if (seen.has(idx)) continue;
    seen.add(idx);
    const datePosted = parseBoardDate(cleanText(dateCell));
    if (!datePosted) continue;
    items.push({
      idx,
      link,
      title: cleanText(linkMatch[2]),
      industry: cleanText(industryCell),
      type: cleanText(typeCell),
      datePosted,
      deadline: parseBoardDate(cleanText(deadlineCell)),
    });
  }
  return items;
}
