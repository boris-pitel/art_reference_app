-- One durable conversation per owned reference; only the authenticated edge
-- function may access it. Library IDs use the application's email-derived UUID.
create table public.reference_ai_chats (
  reference_id uuid primary key references public.image_assets(id) on delete cascade,
  user_id text not null,
  turns jsonb not null default '[]'::jsonb,
  response_id text,
  updated_at timestamptz not null default now()
);
alter table public.reference_ai_chats enable row level security;
revoke all on public.reference_ai_chats from anon, authenticated;
grant all on public.reference_ai_chats to service_role;
