-- Replicates stored images to the offsite backup as they are created and
-- removed, rather than only when someone remembers to run the sweep.
--
-- The database backups restore rows, not stored objects: after a loss every
-- row describing an image would come back and no image would. The reconciler
-- in tool/replicate_to_r2.dart closes that gap in bulk; this closes the window
-- between an upload and the next sweep.
--
-- pg_net sends the request asynchronously, so the trigger returns immediately
-- and the insert that fired it is not delayed waiting for a copy. That is the
-- whole reason this is a trigger rather than work done inside
-- finalize-image-upload: replication that blocks the upload would make the
-- upload fail whenever the backup is unavailable.

create extension if not exists pg_net with schema extensions;

create or replace function public.replicate_image_to_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload jsonb;
begin
  -- Shaped like a Supabase database webhook so the same Edge Function can be
  -- driven by either this trigger or the dashboard's webhook feature.
  payload := jsonb_build_object(
    'type', tg_op,
    'table', tg_table_name,
    'schema', tg_table_schema,
    'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    'old_record', case when tg_op = 'DELETE' then to_jsonb(old) else null end
  );

  -- No credentials are sent. The function authenticates a deletion by
  -- checking the row is genuinely gone rather than by trusting a token, so
  -- there is no secret here to leak or rotate.
  perform extensions.net.http_post(
    url := 'https://bbcgcrbvxmertipdjczu.supabase.co/functions/v1/replicate-to-backup',
    body := payload,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  -- Always succeeds. A backup that cannot be reached must never be able to
  -- fail an upload or block a delete; the reconciler is what catches whatever
  -- this misses.
  return coalesce(new, old);
exception
  when others then
    raise warning 'replicate_image_to_backup failed: %', sqlerrm;
    return coalesce(new, old);
end;
$$;

drop trigger if exists replicate_image_to_backup_insert on public.image_assets;
create trigger replicate_image_to_backup_insert
  after insert on public.image_assets
  for each row
  execute function public.replicate_image_to_backup();

-- Fires before the row goes so the old paths are still readable; the Edge
-- Function re-checks that the row is actually gone before retiring anything,
-- which is what makes a forged delete harmless.
drop trigger if exists replicate_image_to_backup_delete on public.image_assets;
create trigger replicate_image_to_backup_delete
  after delete on public.image_assets
  for each row
  execute function public.replicate_image_to_backup();

revoke all on function public.replicate_image_to_backup() from anon, authenticated;
