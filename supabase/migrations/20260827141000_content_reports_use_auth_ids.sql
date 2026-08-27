-- Report ids belong to the messaging id space, not the image one.
--
-- This project carries two user id spaces. The image tables predate Supabase
-- auth and key on a uuid derived from the user's email; the messaging tables
-- key on auth.uid(). Reporting sits entirely on the messaging side — every
-- column it points at, messages.sender_id, conversations.user_a_id, and
-- user_profiles.auth_user_id, is an auth id — so filing a report identified by
-- the derived id would have stored a reporter who matched nobody in any table
-- the report refers to.
--
-- The table is new and empty, so this is a correction rather than a migration
-- of anything.

drop policy if exists "Users file their own reports" on public.content_reports;

create policy "Users file their own reports"
on public.content_reports for insert to authenticated
with check (reporter_user_id = auth.uid());

comment on column public.content_reports.reporter_user_id is
  'auth.users.id of the person reporting. The messaging id space, matching messages.sender_id and conversations.user_a_id.';

comment on column public.content_reports.reported_user_id is
  'auth.users.id of the person reported.';
