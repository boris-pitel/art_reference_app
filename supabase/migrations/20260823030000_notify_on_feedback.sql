-- Tells support when someone sends feedback.
--
-- Feedback landed in this table and stayed there. Nothing announced it, so a
-- user reporting a problem was only discovered by remembering to open the admin
-- console. A report nobody reads is the same as no report.
--
-- Same shape as the backup replication triggers: fire and forget through
-- pg_net, and never able to fail the insert that fired it. Someone sending
-- feedback about a broken app must not have their feedback rejected because the
-- mail provider is down.

create or replace function public.notify_feedback_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://bbcgcrbvxmertipdjczu.supabase.co/functions/v1/notify-feedback',
    body := jsonb_build_object('type', tg_op, 'record', to_jsonb(new)),
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    -- Recorded rather than warned about: a warning nobody reads is how the
    -- first version of the replication trigger reported success while doing
    -- nothing.
    begin
      insert into public.backup_replication_failures (
        operation, storage_path, error_message
      )
      values ('NOTIFY user_feedback', new.id::text, sqlerrm);
    exception
      when others then
        raise warning 'notify_feedback_received could not record failure: %',
          sqlerrm;
    end;

    return new;
end;
$$;

revoke all on function public.notify_feedback_received() from anon, authenticated;

drop trigger if exists notify_feedback_received on public.user_feedback;
create trigger notify_feedback_received
  after insert on public.user_feedback
  for each row
  execute function public.notify_feedback_received();
