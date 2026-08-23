-- Membership levels for AI usage, and no ceiling for admins.
--
-- The first version had one limit for everyone, which cannot express a paid
-- plan and throttled the owner while testing his own app. Limits now come from
-- a named tier, tiers are rows rather than constants, and an administrator is
-- never refused.

create table if not exists public.ai_quota_tiers (
  tier text primary key,
  per_user_daily int not null,
  per_user_monthly int not null,
  description text,
  updated_at timestamptz not null default now()
);

insert into public.ai_quota_tiers (tier, per_user_daily, per_user_monthly, description)
values
  ('free',    1,  3,   'Enough to see what it does'),
  ('studio',  10, 50,  'Paid — everyday use'),
  ('atelier', 25, 200, 'Paid — heavy use')
on conflict (tier) do nothing;

alter table public.ai_quota_tiers enable row level security;

-- Keyed by email rather than by either user id, because that is the one
-- identifier an administrator can actually read off a screen and type. The two
-- id spaces in this project - the auth uid and the derived storage id - are
-- both opaque, and picking the wrong one is a silent misassignment.
create table if not exists public.user_ai_tier (
  user_email text primary key,
  tier text not null references public.ai_quota_tiers (tier),
  note text,
  updated_at timestamptz not null default now()
);

alter table public.user_ai_tier enable row level security;

alter table public.ai_quota_settings
  add column if not exists default_tier text not null default 'free'
    references public.ai_quota_tiers (tier);

-- Takes one unit of quota, or refuses.
--
-- Admins are counted but never refused: the numbers stay useful for seeing what
-- the service costs, while the person who has to test the feature is not
-- blocked by it. They also pass the service-wide ceiling, which is deliberate -
-- that ceiling exists to contain users, and an administrator turning it off for
-- themselves to investigate is the point.
--
-- Admin status is looked up here rather than passed in. The Edge Function has
-- already verified the token and could hand over a flag, but a permission that
-- travels as an argument is one refactor away from being caller-controlled.
create or replace function public.consume_ai_quota(
  p_user_id text,
  p_operation text,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings public.ai_quota_settings;
  limits public.ai_quota_tiers;
  resolved_tier text;
  is_admin boolean := false;
  today int;
  this_month int;
  everyone_today int;
begin
  select * into settings from public.ai_quota_settings where id;

  if p_email is not null then
    select coalesce(
      (raw_app_meta_data ->> 'is_admin')::boolean, false
    )
    into is_admin
    from auth.users
    where lower(email) = lower(p_email)
    limit 1;
  end if;

  is_admin := coalesce(is_admin, false);

  select coalesce(t.tier, settings.default_tier) into resolved_tier
  from (select 1) as one
  left join public.user_ai_tier t
    on lower(t.user_email) = lower(coalesce(p_email, ''));

  select * into limits
  from public.ai_quota_tiers
  where tier = coalesce(resolved_tier, settings.default_tier);

  insert into public.ai_usage_counters (user_id, operation, period_start, used)
  values (p_user_id, p_operation, current_date, 1)
  on conflict (user_id, operation, period_start)
  do update set used = public.ai_usage_counters.used + 1
  returning used into today;

  if is_admin then
    return jsonb_build_object(
      'allowed', true, 'tier', 'admin', 'unlimited', true, 'used_today', today
    );
  end if;

  select coalesce(sum(used), 0) into this_month
  from public.ai_usage_counters
  where user_id = p_user_id
    and operation = p_operation
    and period_start >= date_trunc('month', current_date);

  select coalesce(sum(used), 0) into everyone_today
  from public.ai_usage_counters
  where operation = p_operation
    and period_start = current_date;

  if today > limits.per_user_daily
     or this_month > limits.per_user_monthly
     or everyone_today > settings.global_daily then
    update public.ai_usage_counters set used = used - 1
    where user_id = p_user_id and operation = p_operation
      and period_start = current_date;

    return jsonb_build_object(
      'allowed', false,
      'tier', resolved_tier,
      'reason', case
        when today > limits.per_user_daily then 'daily'
        when this_month > limits.per_user_monthly then 'monthly'
        else 'service'
      end,
      'limit', case
        when today > limits.per_user_daily then limits.per_user_daily
        when this_month > limits.per_user_monthly then limits.per_user_monthly
        else settings.global_daily
      end
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'tier', resolved_tier,
    'used_today', today,
    'used_this_month', this_month,
    'daily_limit', limits.per_user_daily,
    'monthly_limit', limits.per_user_monthly
  );
end;
$$;

revoke all on function public.consume_ai_quota(text, text, text)
  from anon, authenticated;
