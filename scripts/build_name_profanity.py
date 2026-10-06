import json, re, sys
# Writes the NAME_PROFANE_* constants for index.html (argv[1]) and
# "sql migrations/display_name_profanity_migration.sql" (argv[2]) from ONE set
# of lists, so the page and the database cannot disagree. See CLAUDE.md, "NO
# PROFANITY IN A DISPLAY NAME".
#
# Words no real name contains, matched INSIDE the name (spaces, hyphens and
# apostrophes taken out first). Deliberately absent: shit (Yamashita), cock
# (Hitchcock), fuk (Fukuda), nazi (Nazir), ass (Cassandra), rapist (Therapist),
# dick (a real nickname), cum (Cumberbatch).
ANYWHERE = ['fuck','fvck','cunt','nigger','nigga','faggot','whore','bitch','retard',
            'asshole','asshat','dumbass','jackass','bullshit','shithead','dickhead',
            'cocksucker','dildo','vagina','pussy','jizz','wanker','hitler','motherf']
# Refused only as a whole word of the name, or as the whole name squashed.
WORDS = ['shit','shite','ass','cock','cum','tits','twat','slut','porn','sex','anal','fag',
         'fags','nazi','nazis','kkk','piss','pedo','rape','rapist','penis','boob','boobs',
         'milf','fck','fuk','stfu','cunts','arse','arsehole','bastard','prick']
# Real words that contain an ANYWHERE entry, cut out before that check.
ALLOW = ['scunthorpe']
# Korean, matched inside the name with spaces taken out.
KO = ['씨발','시발','씨빨','씨바','ㅅㅂ','ㅆㅂ','씨8','병신','ㅂㅅ','개새끼','개새기','개색기',
      '개색끼','좆','존나','지랄','미친놈','미친년','엠창','느금마','니미럴','썅','염병','창녀',
      '섹스','강간']
# Whole words matched WITH their marks: Vietnamese (stripped, "lồn" is "lon"),
# and the two Korean words whose syllables also turn up inside ordinary names.
VI = ['보지','자지','địt','đụ','lồn','cặc','buồi','đĩ','đéo','đm','đmm','đcm','dcm','vcl','vkl','clm','cmm']
LEET_FROM, LEET_TO = '01345789', 'oieastbg'

def rep(w):  # letters may repeat: fuuuck
    return ''.join(re.escape(c)+'+' for c in w)

js = f"""const NAME_PROFANE_ANYWHERE = {json.dumps(ANYWHERE)};
const NAME_PROFANE_WORDS = {json.dumps(WORDS)};
const NAME_PROFANE_ALLOW = {json.dumps(ALLOW)};
const NAME_PROFANE_KO = {json.dumps(KO, ensure_ascii=False)};
const NAME_PROFANE_WHOLE = {json.dumps(VI, ensure_ascii=False)};
const NAME_LEET = {json.dumps(dict(zip(LEET_FROM, LEET_TO)))};"""

def alt(ws): return '|'.join(rep(w) for w in ws)
sep = "[[:space:]''-]"
sql = f"""-- No profanity in a display name (real-user rule, 6 Oct: "make sure people
-- can't sign up with an obvious profanity ridden name"). The page refuses it
-- first (isCleanDisplayName() in index.html, with a message); this is the
-- backstop for a name written around the page, through the API.
--
-- GENERATED from the same lists as the page's NAME_PROFANE_* constants
-- (scripts/build_name_profanity.py). Change one, change the other.
--
-- A trigger on INSERT and on a CHANGE of display_name, deliberately not a
-- CHECK constraint: a check is evaluated on every update of the row, so an
-- account already holding a name this refuses could not change its colour or
-- its settings until somebody renamed it. This only ever judges a name being
-- written.
--
-- Differences from the page, both in the safe direction: there is no unaccent
-- here, so "fück" passes this backstop (the page drops accents before it
-- checks), and lower() follows the database's own collation.
create or replace function public.display_name_is_clean(n text)
returns boolean
language sql
immutable
as $$
  with v as (
    select lower(n) as raw,
           translate(lower(n), '{LEET_FROM}', '{LEET_TO}') as leet
  ), s as (
    select raw,
           leet,
           {"".join(f"replace(" for _ in ALLOW)}regexp_replace(leet, '{sep}+', '', 'g'){"".join(f", '{a}', '')" for a in ALLOW)} as squashed,
           regexp_replace(raw, '{sep}+', '', 'g') as raw_squashed
    from v
  )
  select n is null or not (
       squashed ~ '({alt(ANYWHERE)})'
    or leet ~ '(^|{sep})({alt(WORDS)})({sep}|$)'
    or squashed ~ '^({alt(WORDS)})$'
    or raw_squashed ~ '({"|".join(KO)})'
    or raw ~ '(^|{sep})({"|".join(VI)})({sep}|$)'
  )
  from s;
$$;

create or replace function public.guard_display_name_clean()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT' or new.display_name is distinct from old.display_name)
     and not public.display_name_is_clean(new.display_name) then
    raise exception 'display_name_not_allowed' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_display_name_clean on public.profiles;
create trigger profiles_display_name_clean
  before insert or update of display_name on public.profiles
  for each row execute function public.guard_display_name_clean();
"""
open(sys.argv[1],'w',encoding='utf-8').write(js)
open(sys.argv[2],'w',encoding='utf-8').write(sql)
print('ok')
