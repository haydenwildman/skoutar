-- ════════════════════════════════════════════════════════════════════
-- SKOUTAR: RevenueCat purchases -> Supabase (server side only)
-- Run ONCE in the SQL Editor of project xmzdwoqvnnwhbnntziuk. Safe to re-run.
-- Requires supabase_accounts_migration.sql and supabase_pitchers_migration.sql.
--
-- Security model
--   * The app can NEVER mark an account paid. user_subscriptions is read-only
--     for signed-in users (RLS, unchanged).
--   * Only the Edge Function `revenuecat-webhook` (after checking RevenueCat's
--     shared-secret Authorization header) calls apply_revenuecat_event(), which
--     is executable by the service_role ONLY.
--   * Which SKOUTAR plan a purchase buys comes from the STORE PRODUCT id via
--     revenuecat_product_plans, never from anything the client sends.
-- ════════════════════════════════════════════════════════════════════

-- 1. Store product -> SKOUTAR plan (server-side source of truth)
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

-- 2. Webhook event log (dedupe + audit). No client access at all.
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

-- 3. What the last verified purchase looked like
alter table public.user_subscriptions
  add column if not exists rc_product_id       text,
  add column if not exists rc_billing_interval text,
  add column if not exists rc_period_type      text,
  add column if not exists rc_environment      text,
  add column if not exists rc_last_event_ms    bigint;

-- 4. Lock the new tables down (RLS on, no policies, no grants)
alter table public.revenuecat_product_plans enable row level security;
alter table public.revenuecat_events        enable row level security;
revoke all on public.revenuecat_product_plans, public.revenuecat_events from anon, authenticated;

-- 5. The only thing that can mark an account paid
create or replace function public.apply_revenuecat_event(p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_id      text := p->>'id';
  v_type    text := p->>'type';
  v_app     text := p->>'app_user_id';
  v_raw     text := case when p->>'type' = 'PRODUCT_CHANGE'
                         then coalesce(p->>'new_product_id', p->>'product_id')
                         else p->>'product_id' end;
  v_product text := split_part(coalesce(v_raw, ''), ':', 1);  -- Google: "family_monthly:base-plan"
  v_ts      bigint := nullif(p->>'event_timestamp_ms', '')::bigint;
  v_exp     timestamptz := case when nullif(p->>'expiration_at_ms', '') is null then null
                                else to_timestamp((p->>'expiration_at_ms')::bigint / 1000.0) end;
  v_period  text := p->>'period_type';
  v_env     text := p->>'environment';
  v_store   text := lower(coalesce(p->>'store', ''));
  v_uid     uuid;
  v_plan    text;
  v_interval text;
  v_sub     record;
  v_result  text;
begin
  if v_id is null or v_type is null then raise exception 'Malformed event'; end if;

  insert into public.revenuecat_events (event_id, event_type, app_user_id, product_id, event_ts_ms, environment, payload)
  values (v_id, v_type, v_app, nullif(v_product, ''), v_ts, v_env, p)
  on conflict (event_id) do nothing;
  if not found then return 'duplicate'; end if;

  <<body>>
  begin
    if v_type = 'TEST' then v_result := 'test'; exit body; end if;

    -- Only real SKOUTAR accounts: the RevenueCat app user id IS the Supabase auth uuid.
    if v_app is null or v_app !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_result := 'ignored_non_account_user'; exit body;
    end if;
    v_uid := v_app::uuid;
    if not exists (select 1 from auth.users where id = v_uid) then v_result := 'ignored_unknown_user'; exit body; end if;

    select * into v_sub from public.user_subscriptions where owner_id = v_uid for update;
    if not found then v_result := 'retry_no_subscription_row'; exit body; end if;

    if v_ts is not null and v_sub.rc_last_event_ms is not null and v_ts <= v_sub.rc_last_event_ms then
      v_result := 'stale'; exit body;
    end if;

    if v_type in ('INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED') then
      select plan_id, billing_interval into v_plan, v_interval
        from public.revenuecat_product_plans where product_id = v_product;
      if v_plan is null then v_result := 'ignored_unknown_product'; exit body; end if;
      if v_exp is not null and v_exp <= now() then v_result := 'ignored_already_expired'; exit body; end if;

      update public.user_subscriptions set
        plan_id               = v_plan,
        status                = case when v_period = 'TRIAL' then 'trialing' else 'active' end,
        trial_end             = case when v_period = 'TRIAL' then v_exp else trial_end end,
        current_period_end    = v_exp,
        cancel_at_period_end  = false,
        billing_provider      = coalesce(nullif(v_store, ''), billing_provider),
        billing_customer_id   = v_app,
        billing_subscription_id = coalesce(p->>'original_transaction_id', billing_subscription_id),
        rc_product_id         = v_product,
        rc_billing_interval   = v_interval,
        rc_period_type        = v_period,
        rc_environment        = v_env,
        rc_last_event_ms      = coalesce(v_ts, rc_last_event_ms),
        updated_at            = now()
      where id = v_sub.id;
      v_result := 'applied';

    elsif v_type = 'CANCELLATION' then
      -- Cancelled at the store: access normally continues to the end of the paid period.
      if v_sub.rc_product_id is not null and v_product <> '' and v_product <> v_sub.rc_product_id then
        v_result := 'ignored_superseded_product'; exit body;
      end if;
      if p->>'cancel_reason' = 'CUSTOMER_SUPPORT' then   -- refunded: access ends now
        update public.user_subscriptions set status = 'canceled', current_period_end = now(),
               cancel_at_period_end = false, rc_last_event_ms = coalesce(v_ts, rc_last_event_ms), updated_at = now()
         where id = v_sub.id;
        v_result := 'applied_refund';
      else
        update public.user_subscriptions set cancel_at_period_end = true,
               rc_last_event_ms = coalesce(v_ts, rc_last_event_ms), updated_at = now()
         where id = v_sub.id;
        v_result := 'applied';
      end if;

    elsif v_type = 'EXPIRATION' then
      if v_sub.rc_product_id is not null and v_product <> '' and v_product <> v_sub.rc_product_id then
        v_result := 'ignored_superseded_product'; exit body;   -- old product expiring after a plan change
      end if;
      update public.user_subscriptions set status = 'expired', current_period_end = coalesce(v_exp, now()),
             cancel_at_period_end = false, rc_last_event_ms = coalesce(v_ts, rc_last_event_ms), updated_at = now()
       where id = v_sub.id;
      v_result := 'applied';

    elsif v_type = 'BILLING_ISSUE' then
      update public.user_subscriptions set status = 'past_due',
             rc_last_event_ms = coalesce(v_ts, rc_last_event_ms), updated_at = now()
       where id = v_sub.id and status = 'active';
      v_result := 'applied';

    else
      v_result := 'ignored_' || lower(v_type);   -- TRANSFER, SUBSCRIPTION_PAUSED, ... (recorded, no change)
    end if;
  end;

  update public.revenuecat_events set result = v_result where event_id = v_id;
  return v_result;
end $$;

revoke all on function public.apply_revenuecat_event(jsonb) from public, anon, authenticated;
grant execute on function public.apply_revenuecat_event(jsonb) to service_role;

-- 6. get_my_entitlement(): same shape as before, plus the verified-payment fields.
--    `tier` stays 'plus' for everyone (unchanged behaviour: no feature locking).
--    To start requiring payment after the trial, change the tier line below to:
--      case when coalesce(paid, false) or (trial_end is not null and trial_end > now()) then 'plus' else 'basic' end
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

-- Check:
--   select * from public.revenuecat_product_plans;
--   select event_type, result, received_at from public.revenuecat_events order by received_at desc limit 20;
