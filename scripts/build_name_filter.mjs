// Writes the display-name filter in TWO places from ONE set of lists, so the
// page and the database can never disagree about what a name may be:
//
//   index.html                                   between the BEGIN/END markers
//   sql migrations/display_name_profanity_migration.sql
//
//   node scripts/build_name_filter.mjs
//
// Ported from Welcome Korea (lib/displayNameFilter.ts and
// scripts/build-display-name-filter-sql.mjs there, 6 Oct), with the lists kept
// in step and three changes this app needs, because a name here may hold
// spaces, hyphens and apostrophes and is often Vietnamese:
//
//   - WORDS, not the whole name, are what ANYWHERE is searched in. Joined,
//     the Vietnamese "Phuc Kim" is "phuckim" and "Tran Ny" is "tranny". A run
//     of single letters IS joined ("f u c k"), and so is a single letter with
//     the word beside it ("f uck"), since that is how a word gets spaced out.
//   - BUILT (a WHOLE word plus affixes: BigAss, DickHead) is tried on the name
//     with its separators taken out, on every word, and on those joined runs.
//   - Vietnamese is matched as whole words WITH its marks, because stripped,
//     "lồn" is "Lon", which is a name. "tit" is left out of WHOLE for the same
//     reason ("Tít" is a common Vietnamese nickname); "tits" stays.
//
// Re-run after changing a list. The migration is all create-or-replace, so
// running it again in Supabase is safe.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Refused wherever they appear inside a word. */
const ANYWHERE = [
  // English
  "fuck", "fvck", "fck", "phuck", "cunt", "bitch", "biatch", "whore", "nigger",
  "nigga", "faggot", "retard", "dildo", "jizz", "pussy", "bollock", "asshole",
  "arsehole", "blowjob", "handjob", "rimjob", "cocksuck", "wanker", "wanking",
  "slutty", "titty", "titties", "vagina", "scrotum", "testicle", "hitler",
  "pedophile", "paedophile", "wetback", "tranny", "skank", "bullshit",
  "horseshit", "dipshit", "shitty", "shithead", "pornstar", "pornhub",
  "buttplug", "butthole", "deepthroat", "cumshot", "gangbang", "masturbat",
  "killyourself",
  // Korean, romanised
  "sibal", "ssibal", "sibbal", "ssibbal", "shibal", "byungsin", "byungshin", "byeongsin",
  "byeongshin", "gaesaekki", "gaesaeki", "gaesekki", "jiral",
  // Danish
  "fisse", "kneppe", "spasser", "perker", "kælling",
  // Korean
  "씨발", "씨빨", "씨팔", "시발", "시빨", "씨바", "십새", "씹", "좆", "좃", "존나",
  "병신", "븅신", "빙신", "병쉰", "개새끼", "개새기", "개색기", "개색끼", "개세끼",
  "개쌔끼", "새끼", "쌔끼", "지랄", "미친놈", "미친년", "니애미", "느금마", "니기미",
  "엠창", "창녀", "섹스", "걸레", "쌍년", "썅", "후장", "딸딸이",
  "염병", "ㅅㅂ", "ㅆㅂ", "ㅂㅅ", "ㅄ", "ㅈㄹ", "ㅈㄴ", "ㅁㅊ", "ㅅㄲ",
];

/** Real words that contain something in ANYWHERE. */
const ALLOWED = ["scunthorpe", "nigeria"];

/** Refused as a whole word, or built from these and the affixes below. Welcome
 *  Korea has 보지 and 자지 in ANYWHERE; here they are whole words, since as two
 *  syllables they also turn up inside ordinary Korean full names. */
const WHOLE = [
  // English
  "ass", "arse", "anal", "anus", "boob", "boobs", "cock", "cum", "dick", "fag",
  "kike", "chink", "spic", "gook", "coon", "dyke", "nazi", "piss", "porn",
  "prick", "rape", "rapist", "pedo", "semen", "sex", "shit", "slut",
  "tits", "penis", "wank", "clit", "douche", "bastard", "twat", "kkk",
  // Danish
  "pik", "røv", "lort", "hore", "luder", "neger", "pis", "kusse",
  // Korean: ㅗ, a raised middle finger on its own, and the two body words
  "ㅗ", "보지", "자지",
];

/** What goes in FRONT of a WHOLE word to make an insult of it. No "the":
 *  "the" + "rapist" is Therapist. */
const BEFORE = [
  "big", "huge", "fat", "small", "tiny", "little", "my", "your", "mr",
  "mrs", "dumb", "stupid", "jack", "hairy", "smelly", "sweaty", "lick", "suck",
  "eat", "kiss",
  "stor", "lille", "fede", "dum", "din", "min", "bøsse",
];

/** What goes AFTER one. No "ing" and no "y": Cummings, Cocky. */
const AFTER = [
  "head", "face", "hole", "wipe", "hat", "bag", "lord", "king", "master",
  "sucker", "licker", "eater", "lover", "boy", "girl", "s",
  "hoved", "fjæs", "hul", "ansigt", "unge",
];

/** Vietnamese, whole words, compared WITH their marks. */
const WHOLE_MARKED = [
  "địt", "đụ", "lồn", "cặc", "buồi", "đĩ", "đéo", "đm", "đmm", "đcm", "dcm",
  "vcl", "vkl", "clm", "cmm",
];

/** Letters that look Latin and are not. Uppercase Æ and Ø too, so the result
 *  does not depend on what the database's lower() knows. */
const LOOKALIKES = [
  ["А", "a"], ["В", "b"], ["Е", "e"], ["К", "k"], ["М", "m"], ["Н", "h"],
  ["О", "o"], ["Р", "p"], ["С", "c"], ["Т", "t"], ["Х", "x"],
  ["а", "a"], ["е", "e"], ["о", "o"], ["р", "p"], ["с", "c"], ["у", "y"],
  ["х", "x"], ["к", "k"], ["м", "m"], ["і", "i"], ["т", "t"], ["ѕ", "s"],
  ["ј", "j"], ["ԁ", "d"], ["һ", "h"],
  ["Α", "a"], ["Β", "b"], ["Ε", "e"], ["Η", "h"], ["Ι", "i"], ["Κ", "k"],
  ["Μ", "m"], ["Ν", "n"], ["Ο", "o"], ["Ρ", "p"], ["Τ", "t"], ["Υ", "y"],
  ["Χ", "x"], ["Ζ", "z"],
  ["α", "a"], ["ε", "e"], ["ι", "i"], ["κ", "k"], ["ν", "v"], ["ο", "o"],
  ["ρ", "p"], ["τ", "t"], ["υ", "u"], ["χ", "x"],
  ["Æ", "æ"], ["Ø", "ø"],
];
const LEET = [["0", "o"], ["1", "i"], ["3", "e"], ["4", "a"], ["5", "s"], ["7", "t"], ["8", "b"], ["9", "g"]];
const MAX_CHECKED = 40;

// ---- the rule, as patterns both sides embed verbatim
const lookMap = new Map(LOOKALIKES);
const fold = (s) => {
  const plain = s.normalize("NFKD").replace(/[̀-ͯ]/g, "").normalize("NFC");
  let out = "";
  for (const ch of plain) out += lookMap.get(ch) ?? ch;
  return out.toLowerCase();
};
const squeeze = (s) => s.replace(/(.)\1+/gu, "$1");
const unique = (ws) => [...new Set(ws)];
const alternation = (ws) => unique(ws).join("|");
const squeezedList = (ws) => ws.map(squeeze).filter((w, i) => w === ws[i] || [...w].length >= 5);
for (const w of [...ANYWHERE, ...WHOLE, ...BEFORE, ...AFTER, ...ALLOWED]) {
  if (!/^[\p{L}]+$/u.test(fold(w))) throw new Error(`not plain letters: ${w}`);
}
function patterns(squeezed) {
  const f = (ws) => ws.map(fold);
  const anywhere = squeezed ? squeezedList(f(ANYWHERE)) : f(ANYWHERE);
  const whole = squeezed ? squeezedList(f(WHOLE)) : f(WHOLE);
  const before = squeezed ? f(BEFORE).map(squeeze) : f(BEFORE);
  const after = squeezed ? f(AFTER).map(squeeze) : f(AFTER);
  const allowed = squeezed ? f(ALLOWED).map(squeeze) : f(ALLOWED);
  const w = alternation(whole);
  return {
    anywhere: `(${alternation(anywhere)})`,
    built: `^(${alternation(before)}|${w})*(${w})(${alternation(after)}|${w})*$`,
    allowed: `(${alternation(allowed)})`,
  };
}
const P = { plain: patterns(false), squeezed: patterns(true) };
const lookFrom = LOOKALIKES.map(([a]) => a).join("");
const lookTo = LOOKALIKES.map(([, b]) => b).join("");
const leetFrom = LEET.map(([a]) => a).join("");
const leetTo = LEET.map(([, b]) => b).join("");
if ([...lookFrom].length !== [...lookTo].length) throw new Error("look-alike map sides differ");

// ---- the page
const js = `// ---- BEGIN generated by scripts/build_name_filter.mjs. Edit the lists THERE
// and re-run it: it writes this block and the database migration together. ----
// NO PROFANITY IN A DISPLAY NAME (real-user rule, 6 Oct: "make sure people
// can't sign up with an obvious profanity ridden name"). A name is shown on
// every leaderboard, so it is the one free-text field the app judges, and
// "obvious" is the design: refusing a real person's name is worse than letting
// a creative spelling through. The reasoning, the traps and the tests are in
// the script's header and in CLAUDE.md ("NO PROFANITY IN A DISPLAY NAME").
const NAME_FILTER = ${JSON.stringify({
  lookFrom, lookTo, leetFrom, leetTo, max: MAX_CHECKED,
  plain: P.plain, squeezed: P.squeezed, wholeMarked: WHOLE_MARKED,
}, null, 0)};
const NAME_FILTER_RE = (()=>{
  const c = (p)=> ({ anywhere: new RegExp(p.anywhere, 'u'), built: new RegExp(p.built, 'u'), allowed: new RegExp(p.allowed, 'gu') });
  return { plain: c(NAME_FILTER.plain), squeezed: c(NAME_FILTER.squeezed) };
})();
// Accents dropped, Hangul put back together, look-alike Cyrillic and Greek read
// as Latin, lowercase: display_name_fold() in the migration, step for step.
function nameFilterFold(s){
  const plain = s.normalize('NFKD').replace(/[\\u0300-\\u036f]/g, '').normalize('NFC');
  const from = [...NAME_FILTER.lookFrom], to = [...NAME_FILTER.lookTo];
  let out = '';
  for(const ch of plain){ const i = from.indexOf(ch); out += i === -1 ? ch : to[i]; }
  return out.toLowerCase();
}
// Words, and runs where single letters are joined to their neighbours
// ("f u c k", "f uck"): what ANYWHERE is searched in.
function nameFilterRuns(words){
  const runs = [];
  let last = null;
  for(const w of words){
    if(runs.length && ([...w].length === 1 || [...last].length === 1)) runs[runs.length - 1] += w;
    else runs.push(w);
    last = w;
  }
  return runs;
}
function isCleanDisplayName(name){
  const folded = [...nameFilterFold(String(name || ''))].slice(0, NAME_FILTER.max).join('');
  const leetFrom = [...NAME_FILTER.leetFrom], leetTo = [...NAME_FILTER.leetTo];
  const forms = [
    folded.replace(/[0-9]/g, ''),
    [...folded].map(ch=>{ const i = leetFrom.indexOf(ch); return i === -1 ? ch : leetTo[i]; }).join('').replace(/[0-9]/g, '')
  ];
  for(const form of forms){
    const words = form.split(/[ '-]+/).filter(Boolean);
    const runs = nameFilterRuns(words);
    const squashed = words.join('');
    for(const [re, sq] of [[NAME_FILTER_RE.plain, s=>s], [NAME_FILTER_RE.squeezed, s=>s.replace(/(.)\\1+/gu, '$1')]]){
      if(runs.some(r=> re.anywhere.test(sq(r).replace(re.allowed, '_')))) return false;
      if([squashed, ...words, ...runs].some(x=> re.built.test(sq(x)))) return false;
    }
  }
  const marked = String(name || '').normalize('NFC').toLowerCase().split(/[ '-]+/);
  return !marked.some(w=> NAME_FILTER.wholeMarked.includes(w));
}
// ---- END generated name filter ----`;

const htmlPath = path.join(root, "index.html");
let html = fs.readFileSync(htmlPath, "utf8");
const begin = html.indexOf("// ---- BEGIN generated by scripts/build_name_filter.mjs");
const endMark = "// ---- END generated name filter ----";
const end = html.indexOf(endMark);
if (begin === -1 || end === -1 || end < begin) throw new Error("markers not found in index.html");
html = html.slice(0, begin) + js + html.slice(end + endMark.length);
fs.writeFileSync(htmlPath, html);

// ---- the database
const lit = (s) => {
  if (s.includes("'")) throw new Error(`quote in ${s}`);
  return `'${s}'`;
};
const arr = (ws) => `array[${ws.map(lit).join(", ")}]`;
const sql = `-- GENERATED by scripts/build_name_filter.mjs. Do not edit: change the lists
-- there and re-run it, which rewrites this file AND the page's own check in
-- index.html together, so the two can never disagree.
--
-- No profanity in a display name (real-user rule, 6 Oct: "make sure people
-- can't sign up with an obvious profanity ridden name"). The page refuses it
-- first, with a message; this is the same rule in the database, for a name
-- written around the page. All create-or-replace: running it again is safe.
--
-- Only a NEW or CHANGED name is judged: a trigger, deliberately not a CHECK
-- constraint, which runs on every update of the row and would stop an account
-- already holding a refused name from saving its colour or its settings.

-- Accents dropped, Hangul put back together, look-alike Cyrillic and Greek
-- read as Latin, lowercase. nameFilterFold() on the page, step for step.
create or replace function public.display_name_fold(s text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(translate(
    normalize(regexp_replace(normalize(s, NFKD), '[\\u0300-\\u036f]', '', 'g'), NFC),
    ${lit(lookFrom)},
    ${lit(lookTo)}
  ))
$$;

-- isCleanDisplayName() on the page, inverted: true when the name is refused.
create or replace function public.display_name_blocked(dname text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  folded text := left(public.display_name_fold(coalesce(dname, '')), ${MAX_CHECKED});
  form text;
  words text[];
  runs text[];
  w text;
  last text;
  x text;
  sq boolean;
begin
  foreach form in array array[
    regexp_replace(folded, '[0-9]', '', 'g'),
    regexp_replace(translate(folded, ${lit(leetFrom)}, ${lit(leetTo)}), '[0-9]', '', 'g')
  ] loop
    words := array(select t from regexp_split_to_table(form, '[ ''-]+') t where t <> '');
    runs := '{}';
    last := null;
    foreach w in array words loop
      if cardinality(runs) > 0 and (char_length(w) = 1 or char_length(last) = 1) then
        runs[cardinality(runs)] := runs[cardinality(runs)] || w;
      else
        runs := runs || w;
      end if;
      last := w;
    end loop;
    foreach sq in array array[false, true] loop
      foreach x in array runs loop
        if sq then x := regexp_replace(x, '(.)\\1+', '\\1', 'g'); end if;
        if (not sq and regexp_replace(x, ${lit(P.plain.allowed)}, '_', 'g') ~ ${lit(P.plain.anywhere)})
           or (sq and regexp_replace(x, ${lit(P.squeezed.allowed)}, '_', 'g') ~ ${lit(P.squeezed.anywhere)}) then
          return true;
        end if;
      end loop;
      foreach x in array (array[array_to_string(words, '')] || words || runs) loop
        if sq then x := regexp_replace(x, '(.)\\1+', '\\1', 'g'); end if;
        if (not sq and x ~ ${lit(P.plain.built)})
           or (sq and x ~ ${lit(P.squeezed.built)}) then
          return true;
        end if;
      end loop;
    end loop;
  end loop;
  return exists (
    select 1 from regexp_split_to_table(lower(normalize(coalesce(dname, ''), NFC)), '[ ''-]+') t
    where t = any(${arr(WHOLE_MARKED)})
  );
end;
$$;

-- 23514 is a check violation; the message is what the page would show.
create or replace function public.profiles_display_name_clean()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.display_name is not distinct from old.display_name then
    return new;
  end if;
  if public.display_name_blocked(new.display_name) then
    raise exception 'display_name_not_allowed' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_display_name_clean on public.profiles;
create trigger profiles_display_name_clean
  before insert or update of display_name on public.profiles
  for each row execute function public.profiles_display_name_clean();
`;
const sqlPath = path.join(root, "sql migrations", "display_name_profanity_migration.sql");
fs.writeFileSync(sqlPath, sql);
console.log(`wrote index.html block and ${path.relative(root, sqlPath)}`);
