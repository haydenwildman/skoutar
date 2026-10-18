-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR: accounts, subscriptions & security foundation
--
-- Run ONCE in the SQL Editor of the project the app points at
-- (Pitching Analytics, xmzdwoqvnnwhbnntziuk). Safe to re-run.
--
-- What it does (nothing is dropped, no existing rows are deleted):
--   1. Adds profile fields: sports, throws_hand, terms_version, terms_accepted_at
--      + a case-insensitive UNIQUE username index.
--   2. Creates subscription_plans (prices / trial length / limits - all editable
--      here, none hardcoded in the app), user_subscriptions, account_members.
--   3. Turns on Row Level Security for the new tables.
--   4. Blocks signed-in users from changing tier, status or terms columns on
--      profiles (trigger + column privileges), so a modified app or a hand-made
--      API request cannot upgrade itself.
--   5. Adds server-side functions (SECURITY DEFINER) for sign-up completion,
--      entitlement lookup, family/team invites with member limits, and
--      account deletion.
--
-- NO payments are active. Nothing here marks anyone as having paid.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. PROFILES ────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists sports            text[] not null default '{}',
  add column if not exists throws_hand       text,
  add column if not exists terms_version     text,
  add column if not exists terms_accepted_at timestamptz;

do $$ begin
  alter table public.profiles add constraint profiles_throws_hand_chk
    check (throws_hand is null or throws_hand in ('R', 'L'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.profiles add constraint profiles_sports_chk
    check (sports <@ array['baseball', 'softball']::text[]);
exception when duplicate_object then null; end $$;

-- Unique usernames, ignoring case. If old duplicates exist this is skipped with
-- a notice: fix the duplicates, then re-run this file.
do $$ begin
  create unique index if not exists profiles_username_lower_uq
    on public.profiles (lower(username));
exception when unique_violation then
  raise notice 'Duplicate usernames exist - unique index NOT created. Fix them and re-run.';
end $$;

-- ── 2. PLANS / SUBSCRIPTIONS / MEMBERS ─────────────────────────────
create table if not exists public.subscription_plans (
  id                  text primary key check (id ~ '^[a-z_]+$'),
  name                text not null,
  monthly_price_cents integer not null check (monthly_price_cents >= 0),
  currency            text not null default 'usd',
  -- NULL = trial length not decided yet. Set it with:
  --   update public.subscription_plans set trial_days = 14;   (or per plan)
  trial_days          integer check (trial_days is null or trial_days >= 0),
  -- Total people on the subscription INCLUDING the owner. NULL = no limit.
  max_members         integer check (max_members is null or max_members >= 1),
  -- Which app access level an entitled subscription unlocks ('basic' or 'plus').
  grants_tier         text not null default 'plus' check (grants_tier in ('basic', 'plus')),
  description         text,
  features            jsonb not null default '[]'::jsonb,
  sort_order          integer not null default 0,
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

insert into public.subscription_plans
  (id, name, monthly_price_cents, max_members, description, features, sort_order)
values
  ('individual', 'Individual', 499, 1,
   'One individual account.',
   '["One individual account","Full SKOUTAR analytics","Your own private pitching data"]'::jsonb, 1),
  ('family', 'Family', 1499, 3,
   'Up to three people under one subscription.',
   '["Up to 3 people","Each person has their own login","Each person keeps their own personal pitching data"]'::jsonb, 2),
  ('team', 'Team', 1999, null,
   'For baseball and softball teams.',
   '["Built for baseball and softball teams","Multiple users under one subscription","Team access tools (coming soon)"]'::jsonb, 3)
on conflict (id) do nothing;   -- never overwrites prices/trial you edit later

create table if not exists public.user_subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  owner_id                 uuid not null unique references auth.users(id) on delete cascade,
  plan_id                  text not null references public.subscription_plans(id),
  status                   text not null default 'pending'
                           check (status in ('pending', 'trialing', 'active', 'past_due', 'canceled', 'expired')),
  trial_start              timestamptz,
  trial_end                timestamptz,
  current_period_end       timestamptz,
  cancel_at_period_end     boolean not null default false,
  billing_provider         text,   -- 'stripe' | 'apple' | 'google' (future)
  billing_customer_id      text,
  billing_subscription_id  text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create table if not exists public.account_members (
  id               uuid primary key default gen_random_uuid(),
  subscription_id  uuid not null references public.user_subscriptions(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  role             text not null default 'member' check (role in ('owner', 'admin', 'member')),
  status           text not null default 'invited' check (status in ('invited', 'active', 'removed')),
  invited_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  unique (subscription_id, user_id)
);

create index if not exists account_members_user_idx on public.account_members (user_id);

-- Member limit enforced in the database (family = 3 incl. owner, etc.).
create or replace function public.enforce_member_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim integer; cnt integer;
begin
  if new.status in ('invited', 'active') then
    perform 1 from public.user_subscriptions where id = new.subscription_id for update; -- serialize
    select p.max_members into lim
      from public.user_subscriptions s join public.subscription_plans p on p.id = s.plan_id
     where s.id = new.subscription_id;
    if lim is not null then
      select count(*) into cnt from public.account_members
       where subscription_id = new.subscription_id
         and status in ('invited', 'active')
         and id is distinct from new.id;
      if cnt + 1 > lim then
        raise exception 'This plan allows at most % people.', lim using errcode = 'check_violation';
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists account_members_limit on public.account_members;
create trigger account_members_limit
  before insert or update on public.account_members
  for each row execute function public.enforce_member_limit();

-- ── 3. RLS: policies need helper functions (avoids recursive policies) ──
create or replace function public.is_subscription_owner(p_sub uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_subscriptions where id = p_sub and owner_id = auth.uid());
$$;

create or replace function public.is_subscription_member(p_sub uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.account_members
                  where subscription_id = p_sub and user_id = auth.uid() and status = 'active');
$$;

alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;
alter table public.account_members    enable row level security;

-- Clients can only READ. All writes go through the functions below (or the
-- service role from a trusted backend/webhook). No insert/update/delete policies
-- exist, and the privileges are revoked as a second layer.
revoke all on public.subscription_plans, public.user_subscriptions, public.account_members
  from anon, authenticated;
grant select on public.subscription_plans to anon, authenticated;
grant select on public.user_subscriptions, public.account_members to authenticated;

drop policy if exists plans_read_active on public.subscription_plans;
create policy plans_read_active on public.subscription_plans
  for select to anon, authenticated using (active);

drop policy if exists subs_read_own_or_member on public.user_subscriptions;
create policy subs_read_own_or_member on public.user_subscriptions
  for select to authenticated
  using (owner_id = auth.uid() or public.is_subscription_member(id));

drop policy if exists members_read_own_or_owner on public.account_members;
create policy members_read_own_or_owner on public.account_members
  for select to authenticated
  using (user_id = auth.uid() or public.is_subscription_owner(subscription_id));

-- ── 4. PROFILES: users may not change privileged columns ───────────
-- Trigger runs as the CALLER (not security definer), so it blocks API requests
-- made as 'anon'/'authenticated' but lets our SECURITY DEFINER functions, the
-- auth sign-up trigger, the dashboard and the service role through.
create or replace function public.guard_profile_privileged()
returns trigger language plpgsql as $$
begin
  if current_user in ('anon', 'authenticated') then
    if tg_op = 'INSERT' then
      new.tier := 'basic';
      new.status := 'active';
      new.terms_version := null;
      new.terms_accepted_at := null;
    else
      if new.id is distinct from old.id
         or new.tier is distinct from old.tier
         or new.status is distinct from old.status
         or new.terms_version is distinct from old.terms_version
         or new.terms_accepted_at is distinct from old.terms_accepted_at then
        raise exception 'This profile field can only be changed by the server.'
          using errcode = '42501';
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists profiles_guard_privileged on public.profiles;
create trigger profiles_guard_privileged
  before insert or update on public.profiles
  for each row execute function public.guard_profile_privileged();

-- Second layer: signed-in users may only update these columns at all.
revoke update on public.profiles from anon, authenticated;
grant update (settings, pitcher_display_name, sports, throws_hand) on public.profiles to authenticated;

-- ── 5. SERVER FUNCTIONS ────────────────────────────────────────────
create or replace function public.is_username_available(p_username text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(trim(p_username)));
$$;

-- Finishes self-serve sign-up. Reads the choices the person made at sign-up from
-- THEIR auth metadata, validates every value here, then records profile fields,
-- terms acceptance, and creates the plan row (trial only if trial_days > 0).
-- Idempotent: does nothing if terms were already recorded.
create or replace function public.complete_signup()
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  meta jsonb; v_username text; v_sports text[]; v_hand text; v_plan text; v_terms text;
  v_trial integer; v_sub uuid;
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  if exists (select 1 from public.profiles where id = uid and terms_accepted_at is not null) then return; end if;

  select raw_user_meta_data into meta from auth.users where id = uid;
  meta := coalesce(meta, '{}'::jsonb);
  v_username := nullif(trim(meta->>'username'), '');
  v_hand     := meta->>'throws_hand';
  v_plan     := meta->>'plan_id';
  v_terms    := nullif(trim(meta->>'terms_version'), '');

  if jsonb_typeof(meta->'sports') = 'array' then
    select coalesce(array_agg(distinct s), '{}') into v_sports from jsonb_array_elements_text(meta->'sports') s;
  else
    v_sports := '{}';
  end if;

  if v_terms is null then raise exception 'Terms must be accepted.'; end if;
  if v_hand is null or v_hand not in ('R', 'L') then raise exception 'Throwing hand must be R or L.'; end if;
  if cardinality(v_sports) = 0 or not (v_sports <@ array['baseball', 'softball']::text[]) then
    raise exception 'Choose baseball, softball, or both.';
  end if;
  if not exists (select 1 from public.subscription_plans where id = v_plan and active) then
    raise exception 'Unknown plan.';
  end if;
  if v_username is not null then
    if v_username !~ '^[A-Za-z0-9_]{3,20}$' then raise exception 'Username must be 3-20 letters, numbers or underscores.'; end if;
    if exists (select 1 from public.profiles where lower(username) = lower(v_username) and id <> uid) then
      raise exception 'That username is already taken.' using errcode = '23505';
    end if;
  end if;

  update public.profiles
     set sports = v_sports, throws_hand = v_hand,
         terms_version = v_terms, terms_accepted_at = now(),
         username = coalesce(v_username, username)
   where id = uid;

  select trial_days into v_trial from public.subscription_plans where id = v_plan;

  insert into public.user_subscriptions (owner_id, plan_id, status, trial_start, trial_end)
  values (uid, v_plan,
          case when coalesce(v_trial, 0) > 0 then 'trialing' else 'pending' end,
          case when coalesce(v_trial, 0) > 0 then now() end,
          case when coalesce(v_trial, 0) > 0 then now() + make_interval(days => v_trial) end)
  on conflict (owner_id) do nothing
  returning id into v_sub;

  if v_sub is null then select id into v_sub from public.user_subscriptions where owner_id = uid; end if;

  insert into public.account_members (subscription_id, user_id, role, status)
  values (v_sub, uid, 'owner', 'active')
  on conflict (subscription_id, user_id) do nothing;
end $$;

-- What the app is entitled to RIGHT NOW (trial expiry is evaluated here, at read
-- time, so an expired trial stops unlocking features without any scheduled job).
create or replace function public.get_my_entitlement()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  e record;   -- best currently-entitled subscription (own or as a member)
  o record;   -- the person's own subscription, whatever its state
begin
  if uid is null then return jsonb_build_object('tier', 'basic'); end if;

  select s.plan_id, p.name as plan_name, s.status, s.trial_end, p.grants_tier, p.max_members
    into e
    from public.account_members m
    join public.user_subscriptions s on s.id = m.subscription_id
    join public.subscription_plans p on p.id = s.plan_id
   where m.user_id = uid and m.status = 'active'
     and ( (s.status = 'trialing' and s.trial_end > now())
        or (s.status in ('active', 'past_due')
            and (s.current_period_end is null or s.current_period_end > now())) )
   order by (p.grants_tier = 'plus') desc, s.created_at
   limit 1;

  select s.plan_id, p.name as plan_name, s.status, s.trial_end, p.max_members
    into o
    from public.user_subscriptions s join public.subscription_plans p on p.id = s.plan_id
   where s.owner_id = uid;

  return jsonb_build_object(
    'tier',                 coalesce(e.grants_tier, 'basic'),
    'plan_id',              coalesce(e.plan_id, o.plan_id),
    'plan_name',            coalesce(e.plan_name, o.plan_name),
    'subscription_status',  coalesce(e.status, o.status),
    'trial_end',            coalesce(e.trial_end, o.trial_end),
    'max_members',          coalesce(e.max_members, o.max_members)
  );
end $$;

-- Family / team membership. Owner invites by username; the invited person must
-- accept. The member limit trigger above enforces the plan cap.
create or replace function public.invite_member_by_username(p_subscription uuid, p_username text, p_role text default 'member')
returns void language plpgsql security definer set search_path = public as $$
declare target uuid;
begin
  if not public.is_subscription_owner(p_subscription) then
    raise exception 'Only the subscription owner can invite people.' using errcode = '42501';
  end if;
  if p_role not in ('member', 'admin') then raise exception 'Invalid role.'; end if;
  select id into target from public.profiles where lower(username) = lower(trim(p_username));
  if target is null then raise exception 'No user with that username.'; end if;
  if target = auth.uid() then raise exception 'You are already on this subscription.'; end if;
  insert into public.account_members (subscription_id, user_id, role, status, invited_by)
  values (p_subscription, target, p_role, 'invited', auth.uid())
  on conflict (subscription_id, user_id) do update
     set status = 'invited', role = excluded.role, invited_by = auth.uid()
   where public.account_members.status = 'removed';
end $$;

create or replace function public.respond_to_invitation(p_subscription uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.account_members
     set status = case when p_accept then 'active' else 'removed' end
   where subscription_id = p_subscription and user_id = auth.uid() and status = 'invited';
end $$;

create or replace function public.remove_member(p_subscription uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_subscription_owner(p_subscription) or p_user = auth.uid()) then
    raise exception 'Not allowed.' using errcode = '42501';
  end if;
  update public.account_members set status = 'removed'
   where subscription_id = p_subscription and user_id = p_user and role <> 'owner';
end $$;

-- Account deletion. Refuses while a paid subscription is active (future billing
-- must be cancelled first). Deletes the person's pitch data, profile and login.
-- NOTE: when real billing exists, decide what billing/tax records must be
-- retained and keep those (without personal data) instead of deleting them.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Not signed in.' using errcode = '28000'; end if;
  if exists (select 1 from public.user_subscriptions
              where owner_id = uid and status in ('active', 'past_due')) then
    raise exception 'Cancel your active subscription before deleting your account.';
  end if;
  delete from public.pitch_events where user_id = uid;   -- explicit: FK may not cascade
  delete from public.profiles     where id = uid;
  delete from auth.users          where id = uid;        -- cascades bullpen/challenge/subscription rows
end $$;

-- Function permissions: nobody by default, then only who needs them.
revoke execute on function
  public.is_subscription_owner(uuid), public.is_subscription_member(uuid),
  public.is_username_available(text), public.complete_signup(), public.get_my_entitlement(),
  public.invite_member_by_username(uuid, text, text), public.respond_to_invitation(uuid, boolean),
  public.remove_member(uuid, uuid), public.delete_my_account()
  from public;

grant execute on function public.is_username_available(text) to anon, authenticated;
grant execute on function
  public.is_subscription_owner(uuid), public.is_subscription_member(uuid),
  public.complete_signup(), public.get_my_entitlement(),
  public.invite_member_by_username(uuid, text, text), public.respond_to_invitation(uuid, boolean),
  public.remove_member(uuid, uuid), public.delete_my_account()
  to authenticated;

notify pgrst, 'reload schema';

-- Optional checks after running:
--   select id, name, monthly_price_cents, trial_days, max_members from public.subscription_plans order by sort_order;
--   select tgname from pg_trigger where tgname in ('profiles_guard_privileged','account_members_limit');
