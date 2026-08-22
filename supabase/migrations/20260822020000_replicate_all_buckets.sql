-- Extends replication to every table that stores files, not just image_assets.
--
-- Message images, category covers and feedback screenshots were reachable only
-- by running the reconciler by hand, so an image sent in a message stayed
-- unprotected until someone remembered. One parameterised trigger function now
-- covers all four, taking the bucket and the path-bearing columns as trigger
-- arguments rather than existing in four near-identical copies that would
-- drift.
--
-- This does not remove the need for periodic reconciliation. pg_net is
-- fire-and-forget: it does not retry, and a dropped request leaves the row
-- committed with nothing recording that the file was never copied. Triggers
-- make replication prompt; only a comparison of both sides makes it verifiable.

create or replace function public.replicate_file_to_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_bucket text := tg_argv[0];
  path_columns text[] := string_to_array(tg_argv[1], ',');
  payload jsonb;
begin
  payload := jsonb_build_object(
    'type', tg_op,
    'table', tg_table_name,
    'schema', tg_table_schema,
    'bucket', target_bucket,
    'columns', to_jsonb(path_columns),
    'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    'old_record', case when tg_op = 'DELETE' then to_jsonb(old) else null end
  );

  perform net.http_post(
    url := 'https://bbcgcrbvxmertipdjczu.supabase.co/functions/v1/replicate-to-backup',
    body := payload,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  return coalesce(new, old);
exception
  when others then
    -- Never fails the operation that fired it: a backup that cannot be reached
    -- must not be able to stop someone sending a message or leaving feedback.
    -- Recorded rather than merely warned about, because the first version of
    -- this raised a warning nobody read and reported success while replicating
    -- nothing.
    begin
      insert into public.backup_replication_failures (
        operation, storage_path, error_message
      )
      values (
        tg_op || ' ' || tg_table_name,
        target_bucket,
        sqlerrm
      );
    exception
      when others then
        raise warning 'replicate_file_to_backup could not record failure: %', sqlerrm;
    end;

    return coalesce(new, old);
end;
$$;

revoke all on function public.replicate_file_to_backup() from anon, authenticated;

-- image_assets keeps its own triggers from the earlier migration; the rest
-- gain them here. Each names its bucket and the columns holding paths.

drop trigger if exists replicate_message_image_insert on public.messages;
create trigger replicate_message_image_insert
  after insert on public.messages
  for each row
  when (new.image_storage_path is not null)
  execute function public.replicate_file_to_backup(
    'message-images', 'image_storage_path'
  );

drop trigger if exists replicate_message_image_delete on public.messages;
create trigger replicate_message_image_delete
  after delete on public.messages
  for each row
  when (old.image_storage_path is not null)
  execute function public.replicate_file_to_backup(
    'message-images', 'image_storage_path'
  );

-- Cover paths are stored as storage://category-covers/<path>; the Edge
-- Function strips that prefix before looking the object up.
drop trigger if exists replicate_category_cover_insert
  on public.user_category_cover_overrides;
create trigger replicate_category_cover_insert
  after insert or update on public.user_category_cover_overrides
  for each row
  when (new.storage_path is not null)
  execute function public.replicate_file_to_backup(
    'category-covers', 'storage_path'
  );

drop trigger if exists replicate_category_cover_delete
  on public.user_category_cover_overrides;
create trigger replicate_category_cover_delete
  after delete on public.user_category_cover_overrides
  for each row
  when (old.storage_path is not null)
  execute function public.replicate_file_to_backup(
    'category-covers', 'storage_path'
  );

drop trigger if exists replicate_feedback_attachment_insert on public.user_feedback;
create trigger replicate_feedback_attachment_insert
  after insert on public.user_feedback
  for each row
  when (new.attachment_path is not null)
  execute function public.replicate_file_to_backup(
    'feedback-attachments', 'attachment_path'
  );

drop trigger if exists replicate_feedback_attachment_delete on public.user_feedback;
create trigger replicate_feedback_attachment_delete
  after delete on public.user_feedback
  for each row
  when (old.attachment_path is not null)
  execute function public.replicate_file_to_backup(
    'feedback-attachments', 'attachment_path'
  );

-- image_assets moves onto the same parameterised function, so there is one
-- implementation rather than two that can diverge.
drop trigger if exists replicate_image_to_backup_insert on public.image_assets;
create trigger replicate_image_to_backup_insert
  after insert on public.image_assets
  for each row
  execute function public.replicate_file_to_backup(
    'reference-images', 'storage_path,thumbnail_storage_path'
  );

drop trigger if exists replicate_image_to_backup_delete on public.image_assets;
create trigger replicate_image_to_backup_delete
  after delete on public.image_assets
  for each row
  execute function public.replicate_file_to_backup(
    'reference-images', 'storage_path,thumbnail_storage_path'
  );
