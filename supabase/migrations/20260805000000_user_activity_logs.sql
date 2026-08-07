-- Append-only, privacy-safe application activity events.
create table if not exists public.user_activity_logs (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_email text not null,
  session_id uuid not null,
  operation text not null,
  status text not null,
  target_type text,
  target_id text,
  parent_image_id uuid,
  duration_ms integer,
  platform text not null,
  app_version text not null,
  details jsonb not null default '{}'::jsonb,
  error_code text,
  error_message text,
  constraint user_activity_operation_check check (length(trim(operation)) between 1 and 100),
  constraint user_activity_status_check check (status in ('started', 'succeeded', 'failed', 'cancelled')),
  constraint user_activity_duration_check check (duration_ms is null or duration_ms >= 0),
  constraint user_activity_details_size_check check (octet_length(details::text) <= 16384)
);

create index if not exists user_activity_created_index
  on public.user_activity_logs (created_at desc);
create index if not exists user_activity_user_created_index
  on public.user_activity_logs (user_id, created_at desc);
create index if not exists user_activity_session_created_index
  on public.user_activity_logs (session_id, created_at asc);
create index if not exists user_activity_operation_created_index
  on public.user_activity_logs (operation, created_at desc);
create index if not exists user_activity_status_created_index
  on public.user_activity_logs (status, created_at desc);

alter table public.user_activity_logs enable row level security;

drop policy if exists "Users insert their own activity"
  on public.user_activity_logs;
create policy "Users insert their own activity" on public.user_activity_logs
for insert to authenticated with check (
  auth.uid() = user_id
  and lower(trim(user_email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
);

revoke all on table public.user_activity_logs from anon, authenticated;
grant insert on table public.user_activity_logs to authenticated;
grant usage, select on sequence public.user_activity_logs_id_seq to authenticated;
grant all on table public.user_activity_logs to service_role;
grant all on sequence public.user_activity_logs_id_seq to service_role;

-- User deletion must also remove activity rows even when the data UUID differs
-- from the Auth UUID used by this table.
create or replace function public.admin_delete_user_data(target_user_id uuid, target_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  deleted_images integer := 0;
  deleted_categories integer := 0;
  deleted_feedback integer := 0;
  deleted_activity integer := 0;
begin
  if target_user_id is null then raise exception 'target_user_id is required'; end if;
  if target_email is null or length(trim(target_email)) = 0 then raise exception 'target_email is required'; end if;

  delete from public.user_activity_logs
  where lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_activity = row_count;
  delete from public.user_feedback
  where user_id = target_user_id or lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_feedback = row_count;
  delete from public.reference_categories where user_id = target_user_id and is_builtin = false;
  get diagnostics deleted_categories = row_count;
  delete from public.image_assets
  where user_id = target_user_id or lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_images = row_count;

  return jsonb_build_object(
    'deleted_images', deleted_images,
    'deleted_categories', deleted_categories,
    'deleted_feedback', deleted_feedback,
    'deleted_activity', deleted_activity
  );
end;
$$;

revoke all on function public.admin_delete_user_data(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_delete_user_data(uuid, text) to service_role;
