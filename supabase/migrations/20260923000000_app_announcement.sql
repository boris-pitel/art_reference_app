-- One optional, app-wide announcement. Only the admin Edge Function can write it.
alter table public.app_status
  add column if not exists announcement_title text,
  add column if not exists announcement_message text,
  add column if not exists announcement_id uuid;
