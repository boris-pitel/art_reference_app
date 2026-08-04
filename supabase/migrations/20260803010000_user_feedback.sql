-- Private in-app feedback for Painter Reference.
create table if not exists public.user_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_email text not null,
  feedback_type text not null,
  comment text not null,
  status text not null default 'new',
  platform text not null,
  app_version text not null,
  current_screen text,
  attachment_path text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_feedback_type_check check (feedback_type in ('suggestion', 'problem', 'question', 'other')),
  constraint user_feedback_status_check check (status in ('new', 'reviewed', 'planned', 'resolved', 'closed')),
  constraint user_feedback_comment_check check (length(trim(comment)) between 1 and 5000)
);

create index if not exists user_feedback_status_created_index on public.user_feedback (status, created_at desc);
create index if not exists user_feedback_user_created_index on public.user_feedback (user_id, created_at desc);
alter table public.user_feedback enable row level security;

create policy "Users submit their own feedback" on public.user_feedback for insert to authenticated
with check (
  auth.uid() = user_id
  and status = 'new'
  and lower(trim(user_email)) = lower(trim(coalesce(auth.jwt() ->> 'email', '')))
  and (attachment_path is null or (storage.foldername(attachment_path))[1] = auth.uid()::text)
);
create policy "Users read their own feedback" on public.user_feedback for select to authenticated
using (auth.uid() = user_id);

revoke all on table public.user_feedback from anon;
grant insert, select on table public.user_feedback to authenticated;
grant all on table public.user_feedback to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-attachments', 'feedback-attachments', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users upload their feedback attachments" on storage.objects for insert to authenticated
with check (bucket_id = 'feedback-attachments' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users read their feedback attachments" on storage.objects for select to authenticated
using (bucket_id = 'feedback-attachments' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users delete their feedback attachments" on storage.objects for delete to authenticated
using (bucket_id = 'feedback-attachments' and (storage.foldername(name))[1] = auth.uid()::text);

create or replace function public.admin_delete_user_data(target_user_id uuid, target_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  deleted_images integer := 0;
  deleted_categories integer := 0;
  deleted_feedback integer := 0;
begin
  if target_user_id is null then raise exception 'target_user_id is required'; end if;
  if target_email is null or length(trim(target_email)) = 0 then raise exception 'target_email is required'; end if;

  delete from public.user_feedback
  where user_id = target_user_id or lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_feedback = row_count;
  delete from public.reference_categories where user_id = target_user_id and is_builtin = false;
  get diagnostics deleted_categories = row_count;
  delete from public.image_assets
  where user_id = target_user_id or lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_images = row_count;

  return jsonb_build_object('deleted_images', deleted_images, 'deleted_categories', deleted_categories,
    'deleted_feedback', deleted_feedback);
end;
$$;

revoke all on function public.admin_delete_user_data(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_delete_user_data(uuid, text) to service_role;
