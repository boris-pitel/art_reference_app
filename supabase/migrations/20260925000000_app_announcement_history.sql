-- Keep published notices available after the home banner is dismissed or
-- replaced. Only the admin Edge Function writes; signed-in users may read.
create table if not exists public.app_announcements (
  id uuid primary key,
  title text not null check (length(trim(title)) between 1 and 100),
  message text not null check (length(trim(message)) between 1 and 1000),
  audience_kind text not null default 'all'
    check (audience_kind in ('all', 'users', 'platforms')),
  target_user_ids uuid[] not null default '{}',
  target_platforms text[] not null default '{}',
  published_at timestamptz not null default now(),
  published_by text
);

create index if not exists app_announcements_published_at_idx
  on public.app_announcements (published_at desc);

alter table public.app_announcements enable row level security;
-- No client policy: audience filtering is enforced by Edge Functions. A
-- direct SELECT grant would expose notices addressed to other people.

-- Preserve an active notice if the status singleton was populated before this
-- migration. This is harmless on first deployment, when the fields are null.
insert into public.app_announcements (id, title, message, published_at, published_by)
select announcement_id, announcement_title, announcement_message,
       updated_at, updated_by
from public.app_status
where announcement_id is not null
  and announcement_title is not null
  and announcement_message is not null
on conflict (id) do nothing;
