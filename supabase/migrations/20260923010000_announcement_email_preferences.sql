-- Account email is the audience for neutral app update notices. Missing rows
-- mean enabled; users may opt out in Account or from an email link.
create table if not exists public.announcement_email_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  updates_enabled boolean not null default true,
  unsubscribe_token uuid not null unique default gen_random_uuid(),
  updated_at timestamptz not null default now()
);

alter table public.announcement_email_preferences enable row level security;

create policy "Read own announcement email preference"
  on public.announcement_email_preferences for select to authenticated
  using (user_id = auth.uid());

create policy "Set own announcement email preference"
  on public.announcement_email_preferences for insert to authenticated
  with check (user_id = auth.uid());

create policy "Update own announcement email preference"
  on public.announcement_email_preferences for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.announcement_email_preferences from anon;
grant select, insert, update on public.announcement_email_preferences to authenticated;
