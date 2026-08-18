-- Service status flag driving the in-app maintenance gate.
--
-- Single row, enforced by a primary key that can only ever hold `true`. Access
-- is exclusively through Edge Functions on the service role: RLS is enabled
-- with no policies, so anon and authenticated clients cannot read or write the
-- table directly, and a compromised client key cannot take the app down.

create table if not exists public.app_status (
  id boolean primary key default true,
  maintenance_enabled boolean not null default false,
  message text,
  updated_at timestamptz not null default now(),
  updated_by text,
  constraint app_status_singleton check (id)
);

insert into public.app_status (id, maintenance_enabled)
values (true, false)
on conflict (id) do nothing;

alter table public.app_status enable row level security;
