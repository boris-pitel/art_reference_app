-- Reporting offensive content and the people who send it.
--
-- The app carries messages and images between users, which makes it a place
-- where someone can be sent something they did not want. Blocking already
-- exists, but blocking only protects the person who does it: the sender walks
-- away free to do the same to somebody else, and nobody running the service
-- ever learns it happened. This is the other half — the part that reaches the
-- operator.

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),

  -- Who complained. Kept even after the report is closed: a pattern of reports
  -- from one person is as informative as a pattern against one person.
  reporter_user_id uuid not null,
  reporter_email text not null,

  -- Who was complained about. Null only for a report about content whose
  -- author cannot be resolved, which should not happen but is not worth
  -- losing a report over.
  reported_user_id uuid,
  reported_email text,

  subject_type text not null
    check (subject_type in ('message', 'user')),

  message_id uuid,
  conversation_id uuid,

  reason text not null
    check (reason in ('harassment', 'sexual', 'violence', 'spam', 'other')),
  details text
    check (details is null or char_length(details) <= 2000),

  -- What was actually reported, copied at the moment of reporting.
  --
  -- Without this a sender deletes the message and the report becomes a
  -- complaint about nothing. The snapshot is the evidence, and it has to
  -- survive the thing it describes.
  content_snapshot jsonb not null default '{}'::jsonb,

  status text not null default 'open'
    check (status in ('open', 'actioned', 'dismissed')),
  resolved_at timestamptz,
  resolved_by text,
  resolution_note text
);

-- The queue is read newest-first and almost always filtered to what is still
-- open, which is the badge's query too.
create index if not exists content_reports_open_idx
on public.content_reports (created_at desc)
where status = 'open';

create index if not exists content_reports_reported_user_idx
on public.content_reports (reported_user_id, created_at desc);

-- Whether the caller is an operator.
--
-- Reads the claim out of the caller's own token rather than a table, which is
-- the same source the app already uses to decide whether to show the admin
-- screens, so the two cannot drift apart.
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (auth.jwt() -> 'app_metadata' ->> 'is_admin')::boolean,
    false
  )
$$;

comment on function public.is_admin() is
  'True when the caller''s token carries is_admin. The same claim the client reads to decide whether to offer the admin screens.';

alter table public.content_reports enable row level security;

-- Anyone signed in may report, but only as themselves. Without the check a
-- report could be filed in someone else's name, which would turn the queue
-- into a way of attacking people rather than a way of protecting them.
create policy "Users file their own reports"
on public.content_reports for insert to authenticated
with check (reporter_user_id = public.current_app_user_id());

-- Deliberately no select policy for ordinary users, not even for their own
-- reports. Being able to read a report back tells the reporter whether it was
-- acted on, and telling somebody that is a decision for the operator, not a
-- side effect of the schema.
create policy "Operators read every report"
on public.content_reports for select to authenticated
using (public.is_admin());

create policy "Operators resolve reports"
on public.content_reports for update to authenticated
using (public.is_admin())
with check (public.is_admin());

revoke all on public.content_reports from anon;
grant insert, select, update on public.content_reports to authenticated;
grant all on public.content_reports to service_role;

-- Suspension ----------------------------------------------------------------
-- A report that is upheld has to be able to do something. Until now the only
-- consequence available was the reporter blocking the sender, which leaves the
-- sender free to repeat it on the next person.

alter table public.user_profiles
  add column if not exists suspended boolean not null default false;

alter table public.user_profiles
  add column if not exists suspended_at timestamptz;

alter table public.user_profiles
  add column if not exists suspended_reason text;

comment on column public.user_profiles.suspended is
  'Set by an operator acting on an upheld report. Checked before a message is sent and before a user appears in search.';

-- Suspension is applied by an operator and by nobody else; the existing
-- policies let a user update their own profile row, which must not extend to
-- lifting their own suspension.
create or replace function public.reject_self_suspension_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() = 'service_role' or public.is_admin() then
    return new;
  end if;

  if new.suspended is distinct from old.suspended
    or new.suspended_at is distinct from old.suspended_at
    or new.suspended_reason is distinct from old.suspended_reason
  then
    raise exception 'Suspension can only be changed by an operator.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists user_profiles_protect_suspension on public.user_profiles;
create trigger user_profiles_protect_suspension
before update on public.user_profiles
for each row
execute function public.reject_self_suspension_change();
