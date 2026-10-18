-- ════════════════════════════════════════════════════════════════
-- SKOUTAR: Bullpen + Game Mode tables
--
-- Run ONCE in the Supabase SQL editor (Project -> SQL Editor -> New query).
-- Adds three NEW tables. Nothing existing (pitch_events, profiles, ...) is
-- changed, so game statistics cannot be affected by bullpen data.
--
-- Row Level Security: every table is locked so a signed-in user can only
-- read and write their OWN rows (same rule as pitch_events).
-- The Bullpen plan is stored in the existing profiles.settings jsonb column
-- (key "bullpenPlan"), so it needs no table.
-- ════════════════════════════════════════════════════════════════

create table if not exists public.bullpen_sessions (
  id            text primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  bullpen_type  text not null,
  custom_name   text,
  throws_hand   text not null default 'R' check (throws_hand in ('R', 'L')),
  started_at    timestamptz not null,
  ended_at      timestamptz,
  status        text not null default 'active' check (status in ('active', 'paused', 'finished')),
  paused_ms     bigint not null default 0,
  paused_at     timestamptz,
  notes         text,
  plan          jsonb,
  created_at    timestamptz not null default now()
);

create table if not exists public.bullpen_pitches (
  id              text primary key,
  session_id      text not null references public.bullpen_sessions(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  seq             integer not null,
  pitch_type      text not null,
  -- Zone coordinates: (0,0) bottom-left of the strike zone, (1,1) top-right,
  -- catcher's view. Values outside 0..1 are outside the zone.
  target_x        double precision,
  target_y        double precision,
  target_w        double precision,
  target_h        double precision,
  actual_x        double precision,
  actual_y        double precision,
  velocity        double precision,
  result          text,
  notes           text,
  plan_set_index  integer,
  ts              timestamptz not null,
  created_at      timestamptz not null default now()
);

create table if not exists public.challenge_attempts (
  id              text primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  mode            text not null check (mode in ('streak', 'accuracy', 'sequence')),
  difficulty      text not null check (difficulty in ('beginner', 'intermediate', 'advanced', 'elite')),
  pitch_key       text not null default '',
  started_at      timestamptz not null,
  ended_at        timestamptz not null,
  success         boolean not null default false,
  score           integer not null default 0,
  goal            integer not null default 0,
  pitches_thrown  integer not null default 0,
  detail          jsonb not null default '[]'::jsonb,
  end_reason      text not null default '',
  created_at      timestamptz not null default now()
);

create index if not exists bullpen_sessions_user_idx on public.bullpen_sessions (user_id, started_at);
create index if not exists bullpen_pitches_user_idx on public.bullpen_pitches (user_id, ts);
create index if not exists bullpen_pitches_session_idx on public.bullpen_pitches (session_id);
create index if not exists challenge_attempts_user_idx on public.challenge_attempts (user_id, ended_at);

alter table public.bullpen_sessions   enable row level security;
alter table public.bullpen_pitches    enable row level security;
alter table public.challenge_attempts enable row level security;

do $$
declare t text;
begin
  foreach t in array array['bullpen_sessions', 'bullpen_pitches', 'challenge_attempts'] loop
    execute format('drop policy if exists "%1$s_select_own" on public.%1$s', t);
    execute format('drop policy if exists "%1$s_insert_own" on public.%1$s', t);
    execute format('drop policy if exists "%1$s_update_own" on public.%1$s', t);
    execute format('drop policy if exists "%1$s_delete_own" on public.%1$s', t);
    execute format('create policy "%1$s_select_own" on public.%1$s for select using (auth.uid() = user_id)', t);
    execute format('create policy "%1$s_insert_own" on public.%1$s for insert with check (auth.uid() = user_id)', t);
    execute format('create policy "%1$s_update_own" on public.%1$s for update using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
    execute format('create policy "%1$s_delete_own" on public.%1$s for delete using (auth.uid() = user_id)', t);
  end loop;
end $$;

-- Make the API see the new tables right away (otherwise it can take a while
-- and the app reports "table not found").
notify pgrst, 'reload schema';

-- Optional check: should return 3 rows.
-- select table_name from information_schema.tables
--  where table_schema = 'public'
--    and table_name in ('bullpen_sessions', 'bullpen_pitches', 'challenge_attempts');
