-- Prevent repeat delivery when an administrator retries a broadcast.
create table if not exists public.announcement_email_deliveries (
  announcement_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('sending', 'sent', 'failed')),
  provider_id text,
  error_message text,
  updated_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);

alter table public.announcement_email_deliveries enable row level security;
-- Service-role access only: users do not need to see other recipients.
