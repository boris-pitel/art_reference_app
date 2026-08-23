-- Membership level as a column on the user, not a lookup beside them.
--
-- The previous version kept assignments in a side table keyed by email and gave
-- administrators a separate exemption, which meant two mechanisms deciding one
-- thing. A level on the user record is the whole answer: unlimited is a level
-- like any other, and an administrator is somebody who has it.

insert into public.ai_quota_tiers (tier, per_user_daily, per_user_monthly, description)
values ('unlimited', 2147483647, 2147483647, 'No limits — administrators')
on conflict (tier) do update
  set per_user_daily = excluded.per_user_daily,
      per_user_monthly = excluded.per_user_monthly,
      description = excluded.description;

alter table public.user_profiles
  add column if not exists ai_level text
    references public.ai_quota_tiers (tier);

comment on column public.user_profiles.ai_level is
  'Membership level governing AI allowances. Null means the default level in '
  'ai_quota_settings. Administrators default to unlimited.';

-- Carry over anything assigned through the side table before this existed, so
-- the move does not silently demote anyone.
update public.user_profiles p
set ai_level = t.tier
from public.user_ai_tier t
join auth.users u on lower(u.email) = lower(t.user_email)
where p.auth_user_id = u.id
  and p.ai_level is null;

drop table if exists public.user_ai_tier;

-- Takes one unit of quota, or refuses.
--
-- Resolution order: the level on the user record, then unlimited for an
-- administrator who has not been given one explicitly, then the service
-- default. The middle step exists so a newly promoted admin is not throttled
-- while testing the very feature they were promoted to look after.
--
-- Levels are read here rather than passed in. The Edge Function has verified
-- the token and could hand over a level, but a permission travelling as an
-- argument is one refactor away from being caller-controlled.
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
    select
      coalesce((u.raw_app_meta_data ->> 'is_admin')::boolean, false),
      p.ai_level
    into is_admin, resolved_tier
    from auth.users u
    left join public.user_profiles p on p.auth_user_id = u.id
    where lower(u.email) = lower(p_email)
    limit 1;
  end if;

  is_admin := coalesce(is_admin, false);
  resolved_tier := coalesce(
    resolved_tier,
    case when is_admin then 'unlimited' else settings.default_tier end
  );

  select * into limits
  from public.ai_quota_tiers
  where tier = resolved_tier;

  if not found then
    select * into limits
    from public.ai_quota_tiers
    where tier = settings.default_tier;
  end if;

  -- Counted even when unlimited: the numbers are what say what the service
  -- costs, and an unmeasured account is exactly the one that surprises you.
  insert into public.ai_usage_counters (user_id, operation, period_start, used)
  values (p_user_id, p_operation, current_date, 1)
  on conflict (user_id, operation, period_start)
  do update set used = public.ai_usage_counters.used + 1
  returning used into today;

  if resolved_tier = 'unlimited' then
    return jsonb_build_object(
      'allowed', true, 'tier', resolved_tier,
      'unlimited', true, 'used_today', today
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
