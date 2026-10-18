-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR: pitcher profiles under one account  (run AFTER
-- supabase_accounts_migration.sql, which you already ran)
--
-- Run ONCE in the SQL Editor of project xmzdwoqvnnwhbnntziuk. Safe to re-run.
--
-- Model: one login (the account owner) + one subscription; each pitcher is a
-- row in public.pitchers. Every game / pitch / bullpen row now also carries a
-- pitcher_id. Nothing is deleted:
--   * every existing account gets ONE pitcher whose id = the account's user id,
--     so all existing rows already point at a valid pitcher;
--   * existing accounts are recorded as the Individual plan;
--   * profiles.settings (custom pitch types, batter names, bullpen plan) is
--     copied to that first pitcher.
-- Older app builds keep working for the first pitcher (a trigger fills in
-- pitcher_id when an older build doesn't send it).
--
-- All plans unlock every feature. The ONLY difference is the pitcher limit:
--   Individual 1, Family 4, Team 20.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. PLANS: pitcher limits, all-premium ──────────────────────────
alter table public.subscription_plans
  add column if not exists max_pitchers integer check (max_pitchers is null or max_pitchers >= 1);

update public.subscription_plans set
  max_pitchers = 1, max_members = 1, grants_tier = 'plus',
  description = 'One pitcher profile with every SKOUTAR feature.',
  features = '["One pitcher profile","Every SKOUTAR feature"]'::jsonb, updated_at = now()
where id = 'individual';

update public.subscription_plans set
  max_pitchers = 4, max_members = 4, grants_tier = 'plus',
  description = 'One shared login for up to 4 pitchers, every feature.',
  features = '["Up to 4 pitcher profiles","One shared login, switch between pitchers","Every SKOUTAR feature","Each pitcher''s stats stay separate"]'::jsonb, updated_at = now()
where id = 'family';

update public.subscription_plans set
  max_pitchers = 20, max_members = 20, grants_tier = 'plus',
  description = 'One subscription for up to 20 pitchers, every feature.',
  features = '["Up to 20 pitcher profiles","Switch between pitchers in one account","Every SKOUTAR feature","Each pitcher''s stats stay separate"]'::jsonb, updated_at = now()
where id = 'team';

-- ── 2. PITCHERS ────────────────────────────────────────────────────
create table if not exists public.pitchers (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users(id) on delete cascade,
  -- Reserved for a later "pitcher gets their own login" step. Unused for now.
  auth_user_id  uuid references auth.users(id) on delete set null,
  display_name  text not null check (length(trim(display_name)) between 1 and 60),
  username      text not null check (length(trim(username)) between 1 and 40),
  sports        text[] not null default '{}' check (sports <@ array['baseball', 'softball']::text[]),
  throws_hand   text check (throws_hand is null or throws_hand in ('R', 'L')),
  settings      jsonb not null default '{}'::jsonb,
  archived_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- Usernames are unique inside one account (not across all accounts).
create unique index if not exists pitchers_owner_username_uq
  on public.pitchers (owner_id, lower(username)) where archived_at is null;
create index if not exists pitchers_owner_idx on public.pitchers (owner_id);

-- Profile usernames are no longer a global identity (pitchers have the names now).
drop index if exists public.profiles_username_lower_uq;

-- ── 3. EXISTING ACCOUNTS: Individual plan + first pitcher ──────────
insert into public.user_subscriptions (owner_id, plan_id, status)
select p.id, 'individual', 'pending'
  from public.profiles p
 where exists (select 1 from auth.users u where u.id = p.id)
on conflict (owner_id) do nothing;

insert into public.account_members (subscription_id, user_id, role, status)
select s.id, s.owner_id, 'owner', 'active' from public.user_subscriptions s
 where not exists (select 1 from public.account_members m
                    where m.subscription_id = s.id and m.user_id = s.owner_id);

insert into public.pitchers (id, owner_id, display_name, username, sports, throws_hand, settings)
select p.id, p.id,
       left(coalesce(nullif(trim(p.pitcher_display_name), ''), nullif(trim(p.username), ''), 'Pitcher'), 60),
       left(coalesce(nullif(trim(p.username), ''), 'pitcher'), 40),
       coalesce(p.sports, '{}'), p.throws_hand, coalesce(p.settings, '{}'::jsonb)
  from public.profiles p
 where exists (select 1 from auth.users u where u.id = p.id)
on conflict (id) do nothing;

-- ── 4. PER-PITCHER DATA ────────────────────────────────────────────
-- user_id stays = the ACCOUNT OWNER (so every existing RLS policy keeps
-- working). pitcher_id says WHICH pitcher the row belongs to.
create or replace function public.enforce_pitcher_ownership()
returns trigger language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if new.pitcher_id is null then
    new.pitcher_id := new.user_id;   -- older app builds: the account's first pitcher
  end if;
  if tg_op = 'UPDATE' and new.pitcher_id is distinct from old.pitcher_id then
    raise exception 'A record cannot be moved to a different pitcher.' using errcode = '42501';
  end if;
  select exists (
    select 1 from public.pitchers p
     where p.id = new.pitcher_id
       and p.owner_id = new.user_id
       and (tg_op = 'UPDATE' or p.archived_at is null)
  ) into ok;
  if not ok then
    raise exception 'That pitcher does not belong to this account, or was removed.' using errcode = '42501';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['pitch_events', 'bullpen_sessions', 'bullpen_pitches', 'challenge_attempts'] loop
    if to_regclass('public.' || t) is null then
      raise notice 'Table public.% not found - skipped.', t;
      continue;
    end if;
    execute format('alter table public.%I add column if not exists pitcher_id uuid references public.pitchers(id) on delete cascade', t);
    execute format('update public.%1$I t set pitcher_id = t.user_id where t.pitcher_id is null and exists (select 1 from public.pitchers p where p.id = t.user_id)', t);
    execute format('create index if not exists %I on public.%I (pitcher_id)', t || '_pitcher_idx', t);
    execute format('drop trigger if exists %I on public.%I', t || '_pitcher_guard', t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.enforce_pitcher_ownership()', t || '_pitcher_guard', t);
    begin
      execute format('alter table public.%I alter column pitcher_id set not null', t);
    exception when others then
      raise notice 'Could not set pitcher_id NOT NULL on % (rows without a pitcher exist?): %', t, sqlerrm;
    end;
  end loop;
end $$;

-- ── 5. LIMITS (enforced in the database, not just the UI) ──────────
create or replace function public.pitcher_limit_for(p_owner uuid)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce(
    (select coalesce(pl.max_pitchers, 2147483647)
       from public.user_subscriptions s join public.subscription_plans pl on pl.id = s.plan_id
      where s.owner_id = p_owner),
    1);
$$;

create or replace function public.enforce_pitcher_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim integer; cnt integer;
begin
  if new.archived_at is null then
    perform pg_advisory_xact_lock(hashtext('pitcher_limit:' || new.owner_id::text));
    lim := public.pitcher_limit_for(new.owner_id);
    select count(*) into cnt from public.pitchers
     where owner_id = new.owner_id and archived_at is null and id is distinct from new.id;
    if cnt + 1 > lim then
      raise exception 'Your plan allows up to % pitchers.', lim using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists pitchers_limit on public.pitchers;
create trigger pitchers_limit
  before insert or update of archived_at, owner_id on public.pitchers
  for each row execute function public.enforce_pitcher_limit();

-- ── 6. RLS ─────────────────────────────────────────────────────────
alter table public.pitchers enable row level security;
revoke all on public.pitchers from anon, authenticated;
grant select on public.pitchers to authenticated;
grant update (settings) on public.pitchers to authenticated;   -- custom pitch types etc.

drop policy if exists pitchers_select on public.pitchers;
create policy pitchers_select on public.pitchers
  for select to authenticated using (owner_id = auth.uid() or auth_user_id = auth.uid());

drop policy if exists pitchers_update_settings on public.pitchers;
create policy pitchers_update_settings on public.pitchers
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
-- No insert/delete policies: pitchers are created/changed only through the
-- functions below, which validate input and the plan limit.

-- ── 7. FUNCTIONS ───────────────────────────────────────────────────
create or replace function public._validate_pitcher(p_name text, p_username text, p_sports text[], p_hand text)
returns void language plpgsql immutable as $$
begin
  if p_name is null or length(trim(p_name)) not between 1 and 60 then
    raise exception 'Pitcher name must be 1-60 characters.';
  end if;
  if p_username is null or trim(p_username) !~ '^[A-Za-z0-9_]{3,20}$' then
    raise exception 'Username must be 3-20 letters, numbers or underscores.';
  end if;
  if p_sports is null or cardinality(p_sports) = 0 or not (p_sports <@ array['baseball', 'softball']::text[]) then
    raise exception 'Choose baseball, softball, or both.';
  end if;
  if p_hand is null or p_hand not in ('R', 'L') then
    raise exception 'Choose right- or left-handed.';
  end if;
end $$;

create or replace function public.add_pitcher(p_display_name text, p_username text, p_sports text[], p_throws_hand text)
returns uuid language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); new_id uuid;
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  perform public._validate_pitcher(p_display_name, p_username, p_sports, p_throws_hand);
  insert into public.pitchers (owner_id, display_name, username, sports, throws_hand)
  values (uid, trim(p_display_name), trim(p_username), p_sports, p_throws_hand)
  returning id into new_id;
  return new_id;
end $$;

create or replace function public.update_pitcher(p_id uuid, p_display_name text, p_username text, p_sports text[], p_throws_hand text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  perform public._validate_pitcher(p_display_name, p_username, p_sports, p_throws_hand);
  update public.pitchers
     set display_name = trim(p_display_name), username = trim(p_username),
         sports = p_sports, throws_hand = p_throws_hand
   where id = p_id and owner_id = uid and archived_at is null;
  if not found then raise exception 'Pitcher not found.' using errcode = '42501'; end if;
end $$;

-- "Remove" = archive: the pitcher disappears from the list and stops counting
-- toward the plan limit, but their data is kept.
create or replace function public.archive_pitcher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  if (select count(*) from public.pitchers where owner_id = uid and archived_at is null) <= 1 then
    raise exception 'An account needs at least one pitcher profile.';
  end if;
  update public.pitchers set archived_at = now()
   where id = p_id and owner_id = uid and archived_at is null;
  if not found then raise exception 'Pitcher not found.' using errcode = '42501'; end if;
end $$;

-- Safety net: an account with no pitcher gets its first one (same id as the
-- account) from the profile. Called by the app after login if the list is empty.
create or replace function public.ensure_default_pitcher()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.user_subscriptions (owner_id, plan_id, status)
  values (auth.uid(), 'individual', 'pending') on conflict (owner_id) do nothing;
  insert into public.pitchers (id, owner_id, display_name, username, sports, throws_hand, settings)
  select p.id, p.id,
         left(coalesce(nullif(trim(p.pitcher_display_name), ''), nullif(trim(p.username), ''), 'Pitcher'), 60),
         left(coalesce(nullif(trim(p.username), ''), 'pitcher'), 40),
         coalesce(p.sports, '{}'), p.throws_hand, coalesce(p.settings, '{}'::jsonb)
    from public.profiles p
   where p.id = auth.uid()
     and not exists (select 1 from public.pitchers x where x.owner_id = p.id and x.archived_at is null)
  on conflict (id) do nothing;
end $$;

-- Sign-up completion, now with pitchers. Reads the choices from the person's
-- own auth metadata, re-validates all of it, enforces the plan's pitcher limit,
-- records terms acceptance, creates the plan row (trial only if trial_days > 0)
-- and the pitcher profiles. The FIRST pitcher gets the account's own id.
create or replace function public.complete_signup()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  meta jsonb; v_plan text; v_terms text; v_max integer; v_trial integer;
  v_sub uuid; v_list jsonb; item jsonb; i integer := 0; v_sports text[];
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  if exists (select 1 from public.profiles where id = uid and terms_accepted_at is not null) then return; end if;

  select raw_user_meta_data into meta from auth.users where id = uid;
  meta := coalesce(meta, '{}'::jsonb);
  v_plan  := meta->>'plan_id';
  v_terms := nullif(trim(meta->>'terms_version'), '');
  v_list  := meta->'pitchers';

  if v_terms is null then raise exception 'Terms must be accepted.'; end if;
  select max_pitchers, trial_days into v_max, v_trial
    from public.subscription_plans where id = v_plan and active;
  if not found then raise exception 'Unknown plan.'; end if;
  if jsonb_typeof(v_list) is distinct from 'array' or jsonb_array_length(v_list) = 0 then
    raise exception 'Add at least one pitcher.';
  end if;
  if v_max is not null and jsonb_array_length(v_list) > v_max then
    raise exception 'That plan allows up to % pitchers.', v_max;
  end if;

  update public.profiles set terms_version = v_terms, terms_accepted_at = now() where id = uid;

  insert into public.user_subscriptions (owner_id, plan_id, status, trial_start, trial_end)
  values (uid, v_plan,
          case when coalesce(v_trial, 0) > 0 then 'trialing' else 'pending' end,
          case when coalesce(v_trial, 0) > 0 then now() end,
          case when coalesce(v_trial, 0) > 0 then now() + make_interval(days => v_trial) end)
  on conflict (owner_id) do nothing
  returning id into v_sub;
  if v_sub is null then select id into v_sub from public.user_subscriptions where owner_id = uid; end if;

  insert into public.account_members (subscription_id, user_id, role, status)
  select v_sub, uid, 'owner', 'active'
   where not exists (select 1 from public.account_members m
                      where m.subscription_id = v_sub and m.user_id = uid);

  for item in select * from jsonb_array_elements(v_list) loop
    if jsonb_typeof(item->'sports') = 'array' then
      select coalesce(array_agg(distinct s), '{}') into v_sports from jsonb_array_elements_text(item->'sports') s;
    else
      v_sports := '{}';
    end if;
    perform public._validate_pitcher(item->>'display_name', item->>'username', v_sports, item->>'throws_hand');
    insert into public.pitchers (id, owner_id, display_name, username, sports, throws_hand)
    values (case when i = 0 then uid else gen_random_uuid() end, uid,
            trim(item->>'display_name'), trim(item->>'username'), v_sports, item->>'throws_hand')
    on conflict (id) do nothing;
    i := i + 1;
  end loop;

  -- keep the login token small: the pitcher list is no longer needed there
  update auth.users set raw_user_meta_data = raw_user_meta_data - 'pitchers' where id = uid;
end $$;

-- Everyone is entitled to every feature. Plans only differ by pitcher limit.
create or replace function public.get_my_entitlement()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); o record;
begin
  if uid is null then return jsonb_build_object('tier', 'plus'); end if;
  select s.plan_id, p.name as plan_name, s.status, s.trial_end, p.max_pitchers
    into o
    from public.user_subscriptions s join public.subscription_plans p on p.id = s.plan_id
   where s.owner_id = uid;
  return jsonb_build_object(
    'tier',                'plus',
    'plan_id',             o.plan_id,
    'plan_name',           o.plan_name,
    'subscription_status', o.status,
    'trial_end',           o.trial_end,
    'max_pitchers',        coalesce(o.max_pitchers, 1)
  );
end $$;

revoke execute on function
  public._validate_pitcher(text, text, text[], text),
  public.add_pitcher(text, text, text[], text),
  public.update_pitcher(uuid, text, text, text[], text),
  public.archive_pitcher(uuid), public.ensure_default_pitcher(),
  public.pitcher_limit_for(uuid), public.complete_signup(), public.get_my_entitlement()
  from public;
grant execute on function
  public.add_pitcher(text, text, text[], text),
  public.update_pitcher(uuid, text, text, text[], text),
  public.archive_pitcher(uuid), public.ensure_default_pitcher(),
  public.complete_signup(), public.get_my_entitlement()
  to authenticated;

notify pgrst, 'reload schema';

-- Checks after running:
--   select id, name, max_pitchers from public.subscription_plans order by sort_order;
--   select count(*) as pitchers, (select count(*) from public.profiles) as profiles from public.pitchers;
--   select count(*) filter (where pitcher_id is null) as missing from public.pitch_events;   -- expect 0
