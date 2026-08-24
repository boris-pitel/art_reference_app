-- Levels as numbers, and never null.
--
-- Every ai_level was null, which is correct but unreadable: null meant "follow
-- whatever the default is", so looking at the table told you nothing about what
-- anyone actually gets. A number with a NOT NULL default means every row states
-- its level outright, and ordering levels becomes arithmetic rather than a
-- lookup.
--
--   0  Free
--   1  Studio
--   2  Studio Plus
--   9  Unlimited

alter table public.ai_quota_tiers
  add column if not exists level int;

update public.ai_quota_tiers set level = case tier
  when 'free' then 0
  when 'studio' then 1
  when 'studio_plus' then 2
  when 'unlimited' then 9
  else 50
end;

alter table public.ai_quota_tiers
  alter column level set not null;

create unique index if not exists ai_quota_tiers_level_idx
  on public.ai_quota_tiers (level);

-- The overview reads the column being replaced, so it goes first and is
-- rebuilt at the end against the new shape.
drop view if exists public.ai_quota_overview;

-- The old text column is replaced rather than kept alongside: two columns
-- meaning the same thing is how they end up disagreeing.
alter table public.user_profiles
  drop column if exists ai_level;

alter table public.user_profiles
  add column if not exists ai_level int not null default 0
    references public.ai_quota_tiers (level);

comment on column public.user_profiles.ai_level is
  'Membership level: 0 Free, 1 Studio, 2 Studio Plus, 9 Unlimited. Never null; '
  'new accounts start at 0. Administrators are unlimited regardless.';

alter table public.ai_quota_settings
  add column if not exists default_level int not null default 0
    references public.ai_quota_tiers (level);

-- Takes one unit of quota, or refuses.
--
-- Administrators are never refused, whatever level they hold. That is the whole
-- rule now, rather than an exemption that applied only when no level was set:
-- one sentence is easier to trust than a precedence order.
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
  resolved_level int;
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
    into is_admin, resolved_level
    from auth.users u
    left join public.user_profiles p on p.auth_user_id = u.id
    where lower(u.email) = lower(p_email)
    limit 1;
  end if;

  is_admin := coalesce(is_admin, false);
  resolved_level := coalesce(resolved_level, settings.default_level);

  if is_admin then
    resolved_level := 9;
  end if;

  select * into limits
  from public.ai_quota_tiers where level = resolved_level;

  if not found then
    select * into limits
    from public.ai_quota_tiers where level = settings.default_level;
  end if;

  -- Counted even when unlimited: an unmeasured account is the one that
  -- surprises you.
  insert into public.ai_usage_counters (user_id, operation, period_start, used)
  values (p_user_id, p_operation, current_date, 1)
  on conflict (user_id, operation, period_start)
  do update set used = public.ai_usage_counters.used + 1
  returning used into today;

  if limits.tier = 'unlimited' then
    return jsonb_build_object(
      'allowed', true, 'level', limits.level, 'tier', limits.tier,
      'unlimited', true, 'used_today', today
    );
  end if;

  select coalesce(sum(used), 0) into this_month
  from public.ai_usage_counters
  where user_id = p_user_id and operation = p_operation
    and period_start >= date_trunc('month', current_date);

  select coalesce(sum(used), 0) into everyone_today
  from public.ai_usage_counters
  where operation = p_operation and period_start = current_date;

  if today > limits.per_user_daily
     or this_month > limits.per_user_monthly
     or everyone_today > settings.global_daily then
    update public.ai_usage_counters set used = used - 1
    where user_id = p_user_id and operation = p_operation
      and period_start = current_date;

    return jsonb_build_object(
      'allowed', false,
      'level', limits.level,
      'tier', limits.tier,
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
    'level', limits.level,
    'tier', limits.tier,
    'used_today', today,
    'used_this_month', this_month,
    'daily_limit', limits.per_user_daily,
    'monthly_limit', limits.per_user_monthly
  );
end;
$$;

revoke all on function public.consume_ai_quota(text, text, text)
  from anon, authenticated;

create or replace view public.ai_quota_overview as
select
  t.level,
  t.tier,
  t.display_name,
  t.per_user_daily,
  t.per_user_monthly,
  t.description,
  (select count(*) from public.user_profiles p where p.ai_level = t.level)
    as members,
  s.global_daily,
  s.default_level
from public.ai_quota_tiers t
cross join public.ai_quota_settings s
order by t.level;

grant select on public.ai_quota_overview to service_role;

notify pgrst, 'reload schema';
