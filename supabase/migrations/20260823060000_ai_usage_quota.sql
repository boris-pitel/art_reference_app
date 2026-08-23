-- Caps what a signed-in user can spend on AI.
--
-- Authentication was never the weak point: ai-edit-image verifies the access
-- token and derives the caller's identity from it, so the user id cannot be
-- forged. The gap was that a genuine account had no ceiling — one scripted loop
-- against an expensive image model is a bill, not a bug.
--
-- Two ceilings, because they fail differently. A per-user limit stops one
-- account running away. A global daily limit stops everything else: many
-- accounts at once, a mistake in a retry loop, or an abuse route nobody thought
-- of. The second one is the part that makes the worst case survivable rather
-- than merely unlikely.

create table if not exists public.ai_quota_settings (
  id boolean primary key default true constraint one_row check (id),
  per_user_daily int not null default 10,
  per_user_monthly int not null default 50,
  -- Deliberately low while the user base is small. Raising it is a one-line
  -- update; discovering it was too high is a credit card statement.
  global_daily int not null default 60,
  updated_at timestamptz not null default now()
);

insert into public.ai_quota_settings (id) values (true)
on conflict (id) do nothing;

alter table public.ai_quota_settings enable row level security;

create table if not exists public.ai_usage_counters (
  -- The derived identifier the AI functions already work in, not auth.uid():
  -- these two id spaces differ, and mixing them would count nobody.
  user_id text not null,
  operation text not null,
  -- Day buckets, so a daily and a monthly limit both come from one table
  -- without a second counter to keep in step.
  period_start date not null default current_date,
  used int not null default 0,
  primary key (user_id, operation, period_start)
);

create index if not exists ai_usage_counters_period_idx
  on public.ai_usage_counters (period_start desc);

alter table public.ai_usage_counters enable row level security;

comment on table public.ai_usage_counters is
  'Counts chargeable AI calls per user per day. Consumed before the model is '
  'called, and refunded only when the model was never reached.';

-- Takes one unit of quota, or refuses.
--
-- Increments first and checks afterwards, rolling back when over. Checking
-- first would let two simultaneous requests both pass the same check and both
-- proceed, which is exactly the scripted case this exists to stop; the upsert
-- takes a row lock, so the increment is the thing that serialises them.
create or replace function public.consume_ai_quota(
  p_user_id text,
  p_operation text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  limits public.ai_quota_settings;
  today int;
  this_month int;
  everyone_today int;
begin
  select * into limits from public.ai_quota_settings where id;

  insert into public.ai_usage_counters (user_id, operation, period_start, used)
  values (p_user_id, p_operation, current_date, 1)
  on conflict (user_id, operation, period_start)
  do update set used = public.ai_usage_counters.used + 1
  returning used into today;

  select coalesce(sum(used), 0) into this_month
  from public.ai_usage_counters
  where user_id = p_user_id
    and operation = p_operation
    and period_start >= date_trunc('month', current_date);

  select coalesce(sum(used), 0) into everyone_today
  from public.ai_usage_counters
  where operation = p_operation
    and period_start = current_date;

  if today > limits.per_user_daily then
    update public.ai_usage_counters set used = used - 1
    where user_id = p_user_id and operation = p_operation
      and period_start = current_date;

    return jsonb_build_object(
      'allowed', false, 'reason', 'daily',
      'limit', limits.per_user_daily
    );
  end if;

  if this_month > limits.per_user_monthly then
    update public.ai_usage_counters set used = used - 1
    where user_id = p_user_id and operation = p_operation
      and period_start = current_date;

    return jsonb_build_object(
      'allowed', false, 'reason', 'monthly',
      'limit', limits.per_user_monthly
    );
  end if;

  if everyone_today > limits.global_daily then
    update public.ai_usage_counters set used = used - 1
    where user_id = p_user_id and operation = p_operation
      and period_start = current_date;

    -- Named separately so a service-wide stop is never mistaken for one user
    -- being greedy, which would send the wrong message to everyone else.
    return jsonb_build_object(
      'allowed', false, 'reason', 'service',
      'limit', limits.global_daily
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'used_today', today,
    'used_this_month', this_month,
    'daily_limit', limits.per_user_daily,
    'monthly_limit', limits.per_user_monthly
  );
end;
$$;

-- Gives a unit back when the model was never reached, so our own failures do
-- not cost the user their allowance. Only called where no request went out:
-- once OpenAI has been asked, the money is spent whatever happens next.
create or replace function public.refund_ai_quota(
  p_user_id text,
  p_operation text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.ai_usage_counters
  set used = greatest(used - 1, 0)
  where user_id = p_user_id
    and operation = p_operation
    and period_start = current_date;
end;
$$;

revoke all on function public.consume_ai_quota(text, text) from anon, authenticated;
revoke all on function public.refund_ai_quota(text, text) from anon, authenticated;
