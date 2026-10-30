-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR: RevenueCat purchases -> Supabase (server side only)   [v3.1]
-- Run ONCE in the SQL Editor of project xmzdwoqvnnwhbnntziuk. Safe to re-run.
-- Requires supabase_accounts_migration.sql and supabase_pitchers_migration.sql
-- (it checks for them and stops with a clear message if they are missing).
-- Runs as ONE transaction: if anything fails, nothing is changed.
--
-- What it never touches: existing users, profiles, pitchers, pitch data,
-- subscription rows, plan prices, plan names, trial days. It only ADDS tables,
-- columns, functions and one trigger, and replaces the two RevenueCat functions
-- (apply_revenuecat_event, get_my_entitlement).
--
-- Security model
--   * The app can NEVER mark an account paid. user_subscriptions is read-only
--     for signed-in users (RLS, unchanged).
--   * Only the Edge Function `revenuecat-webhook` (after checking RevenueCat's
--     shared-secret Authorization header) calls apply_revenuecat_event(), which
--     is executable by the service_role ONLY.
--   * Which SKOUTAR plan a purchase buys comes from the STORE PRODUCT id via
--     revenuecat_product_plans, never from anything the client sends.
--   * Prices are NOT stored or checked here. The price a customer pays is the one
--     configured in RevenueCat / the stores.
--
-- Access model (unchanged): everyone gets Plus. The subscription only decides
-- the plan and therefore the pitcher limit (Individual 1, Family 4, Team 20).
--
-- Retry model (new in v3.1)
--   * Every webhook event is written to revenuecat_events first (audit trail).
--   * An event is only DONE once processed_at is set. Outcomes that start with
--     'retry' (e.g. the user's subscription row does not exist yet, or an
--     unexpected error) leave processed_at empty, so RevenueCat's redelivery
--     (and the replay trigger below) processes the SAME event again.
--   * Finished events are never applied twice (dedupe by event_id).
-- ════════════════════════════════════════════════════════════════════

begin;

-- 0. Verify the existing SKOUTAR schema (stops here, changing nothing, if not) ──
do $$
declare
  missing text;
  v_def   text;
  s       text;
begin
  select string_agg(t.c, ', ') into missing
    from (values ('public.user_subscriptions'), ('public.subscription_plans'),
                 ('public.account_members'), ('public.pitchers')) t(c)
   where to_regclass(t.c) is null;
  if missing is not null then
    raise exception 'Run supabase_accounts_migration.sql and supabase_pitchers_migration.sql first. Missing tables: %', missing;
  end if;

  select string_agg(t.tbl || '.' || t.col, ', ') into missing
    from (values
      ('user_subscriptions', 'id'),                ('user_subscriptions', 'owner_id'),
      ('user_subscriptions', 'plan_id'),           ('user_subscriptions', 'status'),
      ('user_subscriptions', 'trial_end'),         ('user_subscriptions', 'current_period_end'),
      ('user_subscriptions', 'cancel_at_period_end'),
      ('user_subscriptions', 'billing_provider'),  ('user_subscriptions', 'billing_customer_id'),
      ('user_subscriptions', 'billing_subscription_id'), ('user_subscriptions', 'updated_at'),
      ('subscription_plans', 'id'),                ('subscription_plans', 'name'),
      ('subscription_plans', 'max_pitchers'),      ('subscription_plans', 'grants_tier')
    ) t(tbl, col)
   where not exists (select 1 from information_schema.columns c
                      where c.table_schema = 'public' and c.table_name = t.tbl and c.column_name = t.col);
  if missing is not null then
    raise exception 'Expected columns are missing (%). Run the accounts and pitchers migrations first.', missing;
  end if;

  -- The status values this file writes must be allowed by the existing CHECK.
  select string_agg(pg_get_constraintdef(c.oid), ' ') into v_def
    from pg_constraint c
   where c.conrelid = 'public.user_subscriptions'::regclass and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%status%';
  foreach s in array array['pending', 'trialing', 'active', 'past_due', 'canceled', 'expired'] loop
    if v_def is null or position('''' || s || '''' in v_def) = 0 then
      raise exception 'user_subscriptions.status does not allow ''%''. Existing constraint: %', s, coalesce(v_def, '(none)');
    end if;
  end loop;

  -- Intended setup: every plan unlocks Plus; limits Individual 1, Family 4, Team 20.
  -- This is a CHECK, not an overwrite: if you changed a limit on purpose, edit it here.
  select string_agg(format('%s (max_pitchers=%s, grants_tier=%s)', p.id, p.max_pitchers, p.grants_tier), '; ') into missing
    from public.subscription_plans p
   where (p.id = 'individual' and (p.max_pitchers is distinct from 1  or p.grants_tier <> 'plus'))
      or (p.id = 'family'     and (p.max_pitchers is distinct from 4  or p.grants_tier <> 'plus'))
      or (p.id = 'team'       and (p.max_pitchers is distinct from 20 or p.grants_tier <> 'plus'));
  if missing is not null then
    raise exception 'Plan limits differ from the intended setup (Individual 1 / Family 4 / Team 20, all plus): %. Run supabase_pitchers_migration.sql or fix the rows.', missing;
  end if;
  if (select count(*) from public.subscription_plans where id in ('individual', 'family', 'team')) <> 3 then
    raise exception 'subscription_plans must contain individual, family and team.';
  end if;
end $$;

-- 1. Store product -> SKOUTAR plan (server-side source of truth). No prices. ─────
create table if not exists public.revenuecat_product_plans (
  product_id       text primary key,
  plan_id          text not null references public.subscription_plans(id),
  billing_interval text not null check (billing_interval in ('monthly', 'yearly'))
);

insert into public.revenuecat_product_plans (product_id, plan_id, billing_interval) values
  ('monthly',        'individual', 'monthly'),
  ('yearly',         'individual', 'yearly'),
  ('family_monthly', 'family',     'monthly'),
  ('family_yearly',  'family',     'yearly'),
  ('team_monthly',   'team',       'monthly'),
  ('team_yearly',    'team',       'yearly')
on conflict (product_id) do update
  set plan_id = excluded.plan_id, billing_interval = excluded.billing_interval;

-- 2. Webhook event log (dedupe + audit + retry state). No client access at all. ──
create table if not exists public.revenuecat_events (
  event_id     text primary key,
  event_type   text not null,
  app_user_id  text,
  product_id   text,
  event_ts_ms  bigint,
  environment  text,
  result       text,
  received_at  timestamptz not null default now(),
  payload      jsonb not null
);

alter table public.revenuecat_events
  add column if not exists processed_at     timestamptz,           -- set only when the event is DONE
  add column if not exists attempts         integer not null default 0,
  add column if not exists last_attempt_at  timestamptz,
  add column if not exists last_error       text;

-- Rows written by the earlier (v3.0) function: every result except 'retry*' was final.
-- 'retry_no_subscription_row' rows were wrongly treated as done on redelivery; leaving
-- them without processed_at lets them be applied now.
update public.revenuecat_events
   set processed_at = coalesce(last_attempt_at, received_at), attempts = greatest(attempts, 1)
 where processed_at is null and result is not null and result not like 'retry%';

create index if not exists revenuecat_events_pending_idx
  on public.revenuecat_events (app_user_id, event_ts_ms) where processed_at is null;

-- 3. What the last verified purchase looked like (new columns only) ──────────────
alter table public.user_subscriptions
  add column if not exists rc_product_id       text,
  add column if not exists rc_billing_interval text,
  add column if not exists rc_period_type      text,
  add column if not exists rc_environment      text,
  add column if not exists rc_last_event_ms    bigint,
  add column if not exists rc_end_reason       text;   -- why access ended / will end: refund, revoked, unsubscribe, billing_error ...

-- 4. Lock the new tables down (RLS on, no policies, no grants) ──────────────────
alter table public.revenuecat_product_plans enable row level security;
alter table public.revenuecat_events        enable row level security;
revoke all on public.revenuecat_product_plans, public.revenuecat_events from anon, authenticated;

-- 5. Helpers ────────────────────────────────────────────────────────────────────
-- Milliseconds-since-epoch text -> timestamptz. NULL for empty / non-numeric input.
create or replace function public._rc_ts(p text)
returns timestamptz language sql immutable as $$
  select case when p ~ '^[0-9]{1,15}$' then to_timestamp(p::bigint / 1000.0) end;
$$;

-- 6. The business rules: one RevenueCat event -> user_subscriptions ─────────────
-- Internal. Called only by apply_revenuecat_event(), which owns dedupe, audit and
-- retry bookkeeping. Returns a result label. A label starting with 'retry' means
-- "not done, deliver this event again". Any exception raised in here is caught
-- by the caller, rolled back, recorded, and treated as 'retry_error'.
--
-- Payload field names are RevenueCat's (event wrapper already removed by the
-- Edge Function): id, type, app_user_id, product_id, new_product_id, period_type,
-- store, environment, event_timestamp_ms, expiration_at_ms,
-- grace_period_expiration_at_ms, cancel_reason (CANCELLATION), expiration_reason
-- (EXPIRATION), original_transaction_id.
create or replace function public._rc_process_event(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_type    text := p->>'type';
  v_app     text := p->>'app_user_id';
  v_ts      bigint := case when (p->>'event_timestamp_ms') ~ '^[0-9]{1,18}$' then (p->>'event_timestamp_ms')::bigint end;
  -- PRODUCT_CHANGE: product_id is the OLD product, new_product_id the new one.
  -- Google Play ids look like "family_monthly:base-plan": keep the part before ':'.
  v_product text := split_part(coalesce(
                      case when p->>'type' = 'PRODUCT_CHANGE'
                           then coalesce(nullif(p->>'new_product_id', ''), p->>'product_id')
                           else p->>'product_id' end, ''), ':', 1);
  v_exp     timestamptz := public._rc_ts(p->>'expiration_at_ms');
  v_grace   timestamptz := public._rc_ts(p->>'grace_period_expiration_at_ms');
  v_period  text := upper(coalesce(p->>'period_type', ''));
  v_env     text := p->>'environment';
  v_store   text := lower(coalesce(p->>'store', ''));
  v_reason  text := upper(coalesce(case when p->>'type' = 'EXPIRATION' then p->>'expiration_reason'
                                        else p->>'cancel_reason' end, ''));
  v_uid     uuid;
  v_plan    text;
  v_interval text;
  v_sub     record;
  v_entitled boolean;
  v_new_max integer;
  v_old_max integer;
  v_status  text;
  v_why     text;
begin
  if v_type = 'TEST' then return 'test'; end if;

  -- Event types that never change a SKOUTAR subscription. They are still logged.
  --   SUBSCRIPTION_PAUSED (Google): scheduled to pause at period end; RevenueCat says do not revoke now.
  --   TEMPORARY_ENTITLEMENT_GRANT: <=24h stop-gap during store outages with partial data; a real
  --     INITIAL_PURCHASE or an EXPIRATION follows.
  --   TRANSFER: moves purchases between app user ids; the body has no product/period (see setup guide).
  --   NON_RENEWING_PURCHASE, INVOICE_ISSUANCE, PURCHASE_REDEEMED, ...: not used by SKOUTAR products.
  if v_type not in ('INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED',
                    'REFUND_REVERSED', 'CANCELLATION', 'EXPIRATION', 'BILLING_ISSUE') then
    return 'ignored_' || lower(v_type);
  end if;

  -- Only real SKOUTAR accounts: the RevenueCat app user id IS the Supabase auth uuid.
  if v_app is null or v_app !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return 'ignored_non_account_user';
  end if;
  v_uid := v_app::uuid;
  if not exists (select 1 from auth.users where id = v_uid) then return 'ignored_unknown_user'; end if;

  -- The subscription row is created by complete_signup(). If it is not there yet the
  -- event is NOT finished: it stays pending and is applied on redelivery or as soon as the row appears.
  select * into v_sub from public.user_subscriptions where owner_id = v_uid for update;
  if not found then return 'retry_no_subscription_row'; end if;

  -- Older than something already applied for this account.
  if v_ts is not null and v_sub.rc_last_event_ms is not null and v_ts < v_sub.rc_last_event_ms then
    return 'stale';
  end if;

  -- Is the account currently inside a paid / trial period according to our own row?
  v_entitled := v_sub.status in ('active', 'trialing', 'past_due')
                and (v_sub.current_period_end is null or v_sub.current_period_end > now());

  -- ── Access granted or extended ──────────────────────────────────────────────
  if v_type in ('INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'PRODUCT_CHANGE',
                'SUBSCRIPTION_EXTENDED', 'REFUND_REVERSED') then
    select plan_id, billing_interval into v_plan, v_interval
      from public.revenuecat_product_plans where product_id = v_product;
    if v_plan is null then return 'ignored_unknown_product'; end if;
    -- SKOUTAR sells auto-renewing subscriptions only; a missing end date would mean "forever".
    if v_exp is null then return 'ignored_no_expiration'; end if;
    if v_exp <= now() then return 'ignored_already_expired'; end if;

    -- A downgrade bought mid-period (e.g. Family -> Individual on iOS) only takes effect at the next
    -- renewal, and RevenueCat then sends RENEWAL carrying the new product. Keep the paid-for plan until then.
    if v_type = 'PRODUCT_CHANGE' and v_entitled and v_sub.plan_id <> v_plan then
      select coalesce(max_pitchers, 2147483647) into v_new_max from public.subscription_plans where id = v_plan;
      select coalesce(max_pitchers, 2147483647) into v_old_max from public.subscription_plans where id = v_sub.plan_id;
      if v_new_max < v_old_max then
        update public.user_subscriptions
           set rc_last_event_ms = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)), updated_at = now()
         where id = v_sub.id;
        return 'deferred_downgrade_until_renewal';
      end if;
    end if;

    update public.user_subscriptions set
      plan_id                 = v_plan,
      status                  = case when v_period = 'TRIAL' then 'trialing' else 'active' end,
      trial_end               = case when v_period = 'TRIAL' then v_exp else trial_end end,
      current_period_end      = v_exp,
      -- A renewal / new purchase / product change / uncancel means auto-renew is on. An extension or a
      -- reversed refund says nothing about auto-renew, so those keep whatever was recorded.
      cancel_at_period_end    = case when v_type in ('SUBSCRIPTION_EXTENDED', 'REFUND_REVERSED')
                                     then cancel_at_period_end else false end,
      billing_provider        = coalesce(nullif(v_store, ''), billing_provider),
      billing_customer_id     = v_app,
      billing_subscription_id = coalesce(nullif(p->>'original_transaction_id', ''), billing_subscription_id),
      rc_product_id           = v_product,
      rc_billing_interval     = v_interval,
      rc_period_type          = nullif(v_period, ''),
      rc_environment          = v_env,
      rc_end_reason           = null,
      rc_last_event_ms        = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
      updated_at              = now()
    where id = v_sub.id;
    return case when v_type = 'REFUND_REVERSED' then 'applied_refund_reversed' else 'applied' end;
  end if;

  -- Everything below can end or endanger access. An event about a product the account has
  -- since moved away from must not touch the current one.
  if v_sub.rc_product_id is not null and v_product <> '' and v_product <> v_sub.rc_product_id then
    return 'ignored_superseded_product';
  end if;

  -- ── CANCELLATION: cancelled OR refunded. The reason decides. ────────────────
  if v_type = 'CANCELLATION' then
    if v_reason = 'CUSTOMER_SUPPORT' then
      -- Refund (store support or RevenueCat). Access ends NOW; auto-renew may still be on, and a later
      -- RENEWAL (a new payment) grants access again. Status 'canceled' (not 'expired') marks "cut short".
      update public.user_subscriptions set
        status             = 'canceled',
        current_period_end = least(coalesce(current_period_end, now()), now()),
        rc_end_reason      = 'refund',
        rc_last_event_ms   = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
        updated_at         = now()
      where id = v_sub.id;
      return 'applied_refund';
    end if;

    -- From here on the event is not an end of access; if we are not tracking a live subscription
    -- (e.g. the purchase event is still pending) leave it and do NOT move the ordering watermark.
    if not (v_sub.status in ('active', 'trialing', 'past_due')) then return 'ignored_no_active_subscription'; end if;

    if v_reason = 'BILLING_ERROR' then
      -- Store could not charge. Not an expiration: RevenueCat sends EXPIRATION if the grace / retry
      -- window ends unpaid. Mark past_due; keep access through the grace window when RevenueCat gives one.
      update public.user_subscriptions set
        status             = 'past_due',
        current_period_end = case when v_grace is not null and v_grace > now()
                                       and (current_period_end is null or v_grace > current_period_end)
                                  then v_grace else current_period_end end,
        rc_end_reason      = 'billing_error',
        rc_last_event_ms   = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
        updated_at         = now()
      where id = v_sub.id;
      return 'applied_billing_error';
    end if;

    -- Ordinary cancellation (UNSUBSCRIBE, DEVELOPER_INITIATED, PRICE_INCREASE, UNKNOWN, ...): the customer
    -- paid for the current period, so access CONTINUES until it ends. Only "will not renew" is recorded;
    -- status and the period end stay as they are. The EXPIRATION event ends access when the time comes.
    update public.user_subscriptions set
      cancel_at_period_end = true,
      current_period_end   = case when v_exp is not null and v_exp > now()
                                       and (current_period_end is null or v_exp > current_period_end)
                                  then v_exp else current_period_end end,
      rc_end_reason        = case v_reason when 'PRICE_INCREASE' then 'price_increase'
                                           when 'DEVELOPER_INITIATED' then 'developer_cancelled'
                                           else 'unsubscribe' end,
      rc_last_event_ms     = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
      updated_at           = now()
    where id = v_sub.id;
    return 'applied_cancel_at_period_end';
  end if;

  -- ── EXPIRATION: RevenueCat says access should be removed now. ──────────────
  if v_type = 'EXPIRATION' then
    -- CUSTOMER_SUPPORT = refund, DEVELOPER_INITIATED = revoked by you: access was cut short -> 'canceled'.
    -- Anything else (UNSUBSCRIBE, BILLING_ERROR, PRICE_INCREASE, SUBSCRIPTION_PAUSED, UNKNOWN) = ran out -> 'expired'.
    v_status := case when v_reason in ('CUSTOMER_SUPPORT', 'DEVELOPER_INITIATED') then 'canceled' else 'expired' end;
    v_why    := case v_reason when 'CUSTOMER_SUPPORT' then 'refund'
                              when 'DEVELOPER_INITIATED' then 'revoked'
                              when 'BILLING_ERROR' then 'billing_error'
                              when 'PRICE_INCREASE' then 'price_increase'
                              when 'SUBSCRIPTION_PAUSED' then 'paused'
                              else 'expired' end;
    update public.user_subscriptions set
      status               = v_status,
      current_period_end   = least(coalesce(v_exp, now()), now()),
      cancel_at_period_end = false,
      rc_end_reason        = v_why,
      rc_last_event_ms     = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
      updated_at           = now()
    where id = v_sub.id;
    return case when v_status = 'canceled' then 'applied_revocation' else 'applied_expiration' end;
  end if;

  -- ── BILLING_ISSUE: a charge failed; this alone does NOT end access. ────────
  -- (v_type = 'BILLING_ISSUE')
  if not (v_sub.status in ('active', 'trialing', 'past_due')) then return 'ignored_no_active_subscription'; end if;
  update public.user_subscriptions set
    status             = 'past_due',
    current_period_end = case when v_grace is not null and v_grace > now()
                                   and (current_period_end is null or v_grace > current_period_end)
                              then v_grace else current_period_end end,
    rc_end_reason      = 'billing_error',
    rc_last_event_ms   = greatest(coalesce(rc_last_event_ms, 0), coalesce(v_ts, 0)),
    updated_at         = now()
  where id = v_sub.id;
  return 'applied_billing_issue';
end $$;

-- 7. The only thing the webhook calls: dedupe + audit + retry bookkeeping ───────
create or replace function public.apply_revenuecat_event(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_id     text;
  v_type   text;
  v_ev     public.revenuecat_events%rowtype;
  v_result text;
  v_err    text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'Malformed event'; end if;
  v_id   := nullif(p->>'id', '');
  v_type := nullif(p->>'type', '');
  if v_id is null or v_type is null then raise exception 'Malformed event'; end if;

  -- Log the event first (audit + dedupe key). Redeliveries find the same row.
  insert into public.revenuecat_events (event_id, event_type, app_user_id, product_id, event_ts_ms, environment, payload)
  values (v_id, v_type, p->>'app_user_id',
          nullif(split_part(coalesce(p->>'product_id', ''), ':', 1), ''),
          case when (p->>'event_timestamp_ms') ~ '^[0-9]{1,18}$' then (p->>'event_timestamp_ms')::bigint end,
          p->>'environment', p)
  on conflict (event_id) do nothing;

  -- Lock it so two simultaneous deliveries of the same event are handled one after the other.
  select * into v_ev from public.revenuecat_events where event_id = v_id for update;
  if v_ev.processed_at is not null then return 'duplicate'; end if;   -- already DONE: never apply twice

  -- Run the rules in a sub-transaction: an unexpected error undoes any partial change,
  -- but the event row and its error text survive, and the event stays retryable.
  begin
    v_result := public._rc_process_event(p);
  exception when others then
    v_result := 'retry_error';
    v_err := left(sqlstate || ': ' || sqlerrm, 500);
  end;

  if v_result like 'retry%' then
    update public.revenuecat_events
       set result = v_result, attempts = attempts + 1, last_attempt_at = now(), last_error = v_err
     where event_id = v_id;                                             -- processed_at stays NULL: still pending
  else
    update public.revenuecat_events
       set result = v_result, attempts = attempts + 1, last_attempt_at = now(), last_error = null, processed_at = now()
     where event_id = v_id;
  end if;
  return v_result;
end $$;

-- 8. Replay pending events (oldest first). Used automatically when an account's
--    subscription row is created, and by hand for anything left over. ───────────
create or replace function public.replay_pending_revenuecat_events(p_owner uuid default null, p_limit integer default 200)
returns integer language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  for r in
    select payload from public.revenuecat_events
     where processed_at is null
       and (p_owner is null or lower(app_user_id) = p_owner::text)
     order by event_ts_ms nulls first, received_at
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    perform public.apply_revenuecat_event(r.payload);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.trg_replay_revenuecat_events()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.replay_pending_revenuecat_events(new.owner_id);
  exception when others then
    -- never let billing replay break sign-up
    raise warning 'RevenueCat replay for % failed: %', new.owner_id, sqlerrm;
  end;
  return null;
end $$;

drop trigger if exists user_subscriptions_replay_revenuecat on public.user_subscriptions;
create trigger user_subscriptions_replay_revenuecat
  after insert on public.user_subscriptions
  for each row execute function public.trg_replay_revenuecat_events();

revoke all on function
  public._rc_ts(text), public._rc_process_event(jsonb), public.apply_revenuecat_event(jsonb),
  public.replay_pending_revenuecat_events(uuid, integer), public.trg_replay_revenuecat_events()
  from public, anon, authenticated;
grant execute on function public.apply_revenuecat_event(jsonb) to service_role;
grant execute on function public.replay_pending_revenuecat_events(uuid, integer) to service_role;

-- 9. get_my_entitlement(): same shape the app already reads, plus the verified-payment fields.
--    `tier` stays 'plus' for everyone: subscriptions decide the plan and pitcher limit, never feature access.
--    `paid` = a paid period is running right now (status active/past_due and not past its end date).
--    A cancelled-but-not-yet-ended subscription is still paid=true with cancel_at_period_end=true.
create or replace function public.get_my_entitlement()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); o record;
begin
  if uid is null then return jsonb_build_object('tier', 'plus'); end if;
  select s.plan_id, p.name as plan_name, s.status, s.trial_end, p.max_pitchers,
         s.current_period_end, s.cancel_at_period_end, s.rc_billing_interval,
         (s.status in ('active', 'past_due')
            and (s.current_period_end is null or s.current_period_end > now())) as paid
    into o
    from public.user_subscriptions s join public.subscription_plans p on p.id = s.plan_id
   where s.owner_id = uid;
  return jsonb_build_object(
    'tier',                 'plus',
    'plan_id',              o.plan_id,
    'plan_name',            o.plan_name,
    'subscription_status',  o.status,
    'trial_end',            o.trial_end,
    'max_pitchers',         coalesce(o.max_pitchers, 1),
    'paid',                 coalesce(o.paid, false),
    'current_period_end',   o.current_period_end,
    'cancel_at_period_end', coalesce(o.cancel_at_period_end, false),
    'billing_interval',     o.rc_billing_interval
  );
end $$;

notify pgrst, 'reload schema';

commit;

-- Checks after running:
--   select * from public.revenuecat_product_plans;                       -- the six products
--   select id, max_pitchers, grants_tier from public.subscription_plans order by sort_order;   -- 1 / 4 / 20, plus
--   select event_type, result, attempts, processed_at, last_error, received_at
--     from public.revenuecat_events order by received_at desc limit 20;
--   -- events still waiting (e.g. the account row did not exist yet):
--   select event_id, event_type, app_user_id, result, attempts, last_error
--     from public.revenuecat_events where processed_at is null order by received_at;
--   -- re-run waiting events by hand (service role / SQL editor):
--   select public.replay_pending_revenuecat_events();
