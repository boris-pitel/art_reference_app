create table if not exists public.user_profiles (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  login_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_login_name_trimmed
    check (login_name is null or login_name = btrim(login_name)),
  constraint user_profiles_login_name_length
    check (login_name is null or char_length(login_name) between 1 and 50)
);

create unique index if not exists user_profiles_login_name_unique_idx
on public.user_profiles (lower(login_name))
where login_name is not null;

alter table public.user_profiles enable row level security;

create policy "Users read their own profile"
on public.user_profiles for select to authenticated
using (auth.uid() = auth_user_id);

create policy "Users update their own profile"
on public.user_profiles for update to authenticated
using (auth.uid() = auth_user_id)
with check (auth.uid() = auth_user_id);

grant select, update on public.user_profiles to authenticated;
grant all on public.user_profiles to service_role;

create or replace function public.create_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_login_name text := nullif(btrim(new.raw_user_meta_data ->> 'login_name'), '');
begin
  insert into public.user_profiles (auth_user_id, login_name)
  values (new.id, requested_login_name)
  on conflict (auth_user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_user_profile_after_signup on auth.users;
create trigger create_user_profile_after_signup
after insert on auth.users
for each row execute function public.create_user_profile();

revoke all on function public.create_user_profile() from public;

insert into public.user_profiles (auth_user_id, login_name)
select id, null from auth.users
on conflict (auth_user_id) do nothing;

create or replace function public.set_user_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_user_profile_updated_at on public.user_profiles;
create trigger set_user_profile_updated_at
before update on public.user_profiles
for each row execute function public.set_user_profile_updated_at();

revoke all on function public.set_user_profile_updated_at() from public;

create or replace function public.is_login_name_available(candidate text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when nullif(btrim(candidate), '') is null then true
    else not exists (
      select 1
      from public.user_profiles
      where lower(login_name) = lower(btrim(candidate))
    )
  end;
$$;

revoke all on function public.is_login_name_available(text)
from public, anon, authenticated;
grant execute on function public.is_login_name_available(text)
to anon, authenticated, service_role;
