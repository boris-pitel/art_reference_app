-- Corrects the pg_net call and stops the trigger hiding its own failures.
--
-- The first version called extensions.net.http_post. pg_net's functions live
-- in the net schema, so every call raised undefined_function — and the
-- exception handler turned that into a warning nobody reads. The trigger
-- reported success while replicating nothing, which is precisely the failure
-- shape this whole backup exists to defend against.
--
-- Failures are now recorded in a table instead of only a log line, so a
-- replication that stops working is visible in a query rather than only in
-- Postgres logs that roll off after a week.

create table if not exists public.backup_replication_failures (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  operation text not null,
  image_id uuid,
  storage_path text,
  error_message text not null
);

alter table public.backup_replication_failures enable row level security;
revoke all on table public.backup_replication_failures from anon, authenticated;

create or replace function public.replicate_image_to_backup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload jsonb;
begin
  payload := jsonb_build_object(
    'type', tg_op,
    'table', tg_table_name,
    'schema', tg_table_schema,
    'record', case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    'old_record', case when tg_op = 'DELETE' then to_jsonb(old) else null end
  );

  -- pg_net installs into the net schema. Fully qualified because this function
  -- runs with an empty search_path.
  perform net.http_post(
    url := 'https://bbcgcrbvxmertipdjczu.supabase.co/functions/v1/replicate-to-backup',
    body := payload,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  return coalesce(new, old);
exception
  when others then
    -- Still never fails the upload or the delete — a backup that cannot be
    -- reached must not be able to stop the app working. But the failure is now
    -- written down, so it can be found before the backup is needed.
    begin
      insert into public.backup_replication_failures (
        operation, image_id, storage_path, error_message
      )
      values (
        tg_op,
        coalesce(new.id, old.id),
        coalesce(new.storage_path, old.storage_path),
        sqlerrm
      );
    exception
      when others then
        raise warning 'replicate_image_to_backup could not record failure: %', sqlerrm;
    end;

    return coalesce(new, old);
end;
$$;

revoke all on function public.replicate_image_to_backup() from anon, authenticated;
