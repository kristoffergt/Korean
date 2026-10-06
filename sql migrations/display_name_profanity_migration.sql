-- No profanity in a display name (real-user rule, 6 Oct: "make sure people
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
           translate(lower(n), '01345789', 'oieastbg') as leet
  ), s as (
    select raw,
           leet,
           replace(regexp_replace(leet, '[[:space:]''-]+', '', 'g'), 'scunthorpe', '') as squashed,
           regexp_replace(raw, '[[:space:]''-]+', '', 'g') as raw_squashed
    from v
  )
  select n is null or not (
       squashed ~ '(f+u+c+k+|f+v+c+k+|c+u+n+t+|n+i+g+g+e+r+|n+i+g+g+a+|f+a+g+g+o+t+|w+h+o+r+e+|b+i+t+c+h+|r+e+t+a+r+d+|a+s+s+h+o+l+e+|a+s+s+h+a+t+|d+u+m+b+a+s+s+|j+a+c+k+a+s+s+|b+u+l+l+s+h+i+t+|s+h+i+t+h+e+a+d+|d+i+c+k+h+e+a+d+|c+o+c+k+s+u+c+k+e+r+|d+i+l+d+o+|v+a+g+i+n+a+|p+u+s+s+y+|j+i+z+z+|w+a+n+k+e+r+|h+i+t+l+e+r+|m+o+t+h+e+r+f+)'
    or leet ~ '(^|[[:space:]''-])(s+h+i+t+|s+h+i+t+e+|a+s+s+|c+o+c+k+|c+u+m+|t+i+t+s+|t+w+a+t+|s+l+u+t+|p+o+r+n+|s+e+x+|a+n+a+l+|f+a+g+|f+a+g+s+|n+a+z+i+|n+a+z+i+s+|k+k+k+|p+i+s+s+|p+e+d+o+|r+a+p+e+|r+a+p+i+s+t+|p+e+n+i+s+|b+o+o+b+|b+o+o+b+s+|m+i+l+f+|f+c+k+|f+u+k+|s+t+f+u+|c+u+n+t+s+|a+r+s+e+|a+r+s+e+h+o+l+e+|b+a+s+t+a+r+d+|p+r+i+c+k+)([[:space:]''-]|$)'
    or squashed ~ '^(s+h+i+t+|s+h+i+t+e+|a+s+s+|c+o+c+k+|c+u+m+|t+i+t+s+|t+w+a+t+|s+l+u+t+|p+o+r+n+|s+e+x+|a+n+a+l+|f+a+g+|f+a+g+s+|n+a+z+i+|n+a+z+i+s+|k+k+k+|p+i+s+s+|p+e+d+o+|r+a+p+e+|r+a+p+i+s+t+|p+e+n+i+s+|b+o+o+b+|b+o+o+b+s+|m+i+l+f+|f+c+k+|f+u+k+|s+t+f+u+|c+u+n+t+s+|a+r+s+e+|a+r+s+e+h+o+l+e+|b+a+s+t+a+r+d+|p+r+i+c+k+)$'
    or raw_squashed ~ '(씨발|시발|씨빨|씨바|ㅅㅂ|ㅆㅂ|씨8|병신|ㅂㅅ|개새끼|개새기|개색기|개색끼|좆|존나|지랄|미친놈|미친년|엠창|느금마|니미럴|썅|염병|창녀|섹스|강간)'
    or raw ~ '(^|[[:space:]''-])(보지|자지|địt|đụ|lồn|cặc|buồi|đĩ|đéo|đm|đmm|đcm|dcm|vcl|vkl|clm|cmm)([[:space:]''-]|$)'
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
