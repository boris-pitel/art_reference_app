-- The levels as they are actually called, with names fit to show a person.
--
-- 'atelier' was my invention; the levels are Free, Studio and Studio Plus.
-- Renaming rather than adding, so there is never a moment where both exist and
-- somebody is assigned the one that is about to disappear.

alter table public.ai_quota_tiers
  add column if not exists display_name text;

alter table public.ai_quota_tiers
  add column if not exists sort_order int not null default 0;

-- The level is referenced by user_profiles.ai_level, so the new row has to
-- exist before anyone can point at it and the old one cannot be removed until
-- nobody does.
insert into public.ai_quota_tiers
  (tier, per_user_daily, per_user_monthly, description)
values
  ('studio_plus', 25, 200, 'Paid - heavy use')
on conflict (tier) do nothing;

update public.user_profiles
set ai_level = 'studio_plus'
where ai_level = 'atelier';

delete from public.ai_quota_tiers where tier = 'atelier';

update public.ai_quota_tiers set
  display_name = case tier
    when 'free' then 'Free'
    when 'studio' then 'Studio'
    when 'studio_plus' then 'Studio Plus'
    when 'unlimited' then 'Unlimited'
    else initcap(replace(tier, '_', ' '))
  end,
  sort_order = case tier
    when 'free' then 1
    when 'studio' then 2
    when 'studio_plus' then 3
    when 'unlimited' then 99
    else 50
  end;

alter table public.ai_quota_tiers
  alter column display_name set not null;

-- Everything an administrator needs to see and change in one place, so editing
-- a level does not mean knowing which of four tables to open.
create or replace view public.ai_quota_overview as
select
  t.tier,
  t.display_name,
  t.per_user_daily,
  t.per_user_monthly,
  t.description,
  t.sort_order,
  (select count(*) from public.user_profiles p where p.ai_level = t.tier)
    as members,
  s.global_daily,
  s.default_tier
from public.ai_quota_tiers t
cross join public.ai_quota_settings s
order by t.sort_order;
