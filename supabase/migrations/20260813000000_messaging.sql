--
-- Discoverability: public by default, users can opt out.
--
alter table public.user_profiles
  add column if not exists is_discoverable boolean not null default true;

--
-- Blocks. Only the blocker can see or manage their own block rows.
--
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_id_idx
on public.user_blocks (blocked_id);

alter table public.user_blocks enable row level security;

create policy "Users manage their own blocks"
on public.user_blocks for all to authenticated
using (auth.uid() = blocker_id)
with check (auth.uid() = blocker_id);

grant select, insert, delete on public.user_blocks to authenticated;
grant all on public.user_blocks to service_role;

--
-- Conversations: one row per unordered pair of participants.
-- user_a_id is always the lexicographically smaller uuid so a pair can
-- never produce two rows.
--
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references auth.users(id) on delete cascade,
  user_b_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  constraint conversations_distinct_users check (user_a_id <> user_b_id),
  constraint conversations_ordered_users check (user_a_id < user_b_id)
);

create unique index if not exists conversations_unique_pair_idx
on public.conversations (user_a_id, user_b_id);

create index if not exists conversations_user_a_idx
on public.conversations (user_a_id, last_message_at desc);

create index if not exists conversations_user_b_idx
on public.conversations (user_b_id, last_message_at desc);

alter table public.conversations enable row level security;

create policy "Participants read their conversations"
on public.conversations for select to authenticated
using (auth.uid() = user_a_id or auth.uid() = user_b_id);

grant select on public.conversations to authenticated;
grant all on public.conversations to service_role;

--
-- Messages. Writes only ever happen through public.send_message(), called
-- by the send-message edge function with the service role key, so there
-- is no insert policy for the authenticated role.
--
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text,
  image_storage_path text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint messages_has_content
    check (body is not null or image_storage_path is not null),
  constraint messages_body_trimmed
    check (body is null or body = btrim(body)),
  constraint messages_body_not_empty
    check (body is null or char_length(body) > 0),
  constraint messages_body_length
    check (body is null or char_length(body) <= 2000)
);

create index if not exists messages_conversation_idx
on public.messages (conversation_id, created_at);

alter table public.messages enable row level security;

create policy "Participants read messages in their conversations"
on public.messages for select to authenticated
using (
  exists (
    select 1
    from public.conversations c
    where c.id = conversation_id
      and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
  )
);

-- Recipients can mark messages as read; senders never need to update rows.
create policy "Recipients mark messages as read"
on public.messages for update to authenticated
using (
  sender_id <> auth.uid()
  and exists (
    select 1
    from public.conversations c
    where c.id = conversation_id
      and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
  )
)
with check (sender_id <> auth.uid());

grant select, update on public.messages to authenticated;
grant all on public.messages to service_role;

--
-- Atomically enforces blocking, finds-or-creates the conversation, and
-- inserts the message. Only callable by the service role: the calling
-- edge function is responsible for verifying the caller's real identity
-- from their auth session before passing p_sender_id in.
--
create or replace function public.send_message(
  p_sender_id uuid,
  p_recipient_id uuid,
  p_body text,
  p_image_storage_path text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_a uuid;
  v_user_b uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if p_sender_id = p_recipient_id then
    raise exception 'You can''t message yourself.' using errcode = 'P0001';
  end if;

  if not exists (select 1 from auth.users where id = p_recipient_id) then
    raise exception 'That user no longer exists.' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.user_blocks
    where blocker_id = p_recipient_id and blocked_id = p_sender_id
  ) then
    raise exception 'You''re blocked by this user.' using errcode = 'P0003';
  end if;

  if exists (
    select 1 from public.user_blocks
    where blocker_id = p_sender_id and blocked_id = p_recipient_id
  ) then
    raise exception 'You''ve blocked this user. Unblock them to send a message.'
      using errcode = 'P0004';
  end if;

  v_user_a := least(p_sender_id, p_recipient_id);
  v_user_b := greatest(p_sender_id, p_recipient_id);

  insert into public.conversations (user_a_id, user_b_id, last_message_at)
  values (v_user_a, v_user_b, now())
  on conflict (user_a_id, user_b_id)
  do update set last_message_at = excluded.last_message_at
  returning id into v_conversation_id;

  insert into public.messages (conversation_id, sender_id, body, image_storage_path)
  values (v_conversation_id, p_sender_id, p_body, p_image_storage_path)
  returning id, public.messages.created_at into v_message_id, v_created_at;

  return query select v_message_id, v_conversation_id, v_created_at;
end;
$$;

revoke all on function public.send_message(uuid, uuid, text, text)
from public, anon, authenticated;
grant execute on function public.send_message(uuid, uuid, text, text)
to service_role;
