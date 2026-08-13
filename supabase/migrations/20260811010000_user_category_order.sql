create table if not exists public.user_category_order (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  category_code text not null,
  position integer not null check (position >= 0),
  updated_at timestamptz not null default now(),
  primary key (auth_user_id, category_code)
);

create index if not exists user_category_order_position_idx
on public.user_category_order (auth_user_id, position);

alter table public.user_category_order enable row level security;

create policy "Users read their category order"
on public.user_category_order for select to authenticated
using (auth.uid() = auth_user_id);

create policy "Users create their category order"
on public.user_category_order for insert to authenticated
with check (auth.uid() = auth_user_id);

create policy "Users update their category order"
on public.user_category_order for update to authenticated
using (auth.uid() = auth_user_id)
with check (auth.uid() = auth_user_id);

create policy "Users delete their category order"
on public.user_category_order for delete to authenticated
using (auth.uid() = auth_user_id);

grant select, insert, update, delete
on public.user_category_order to authenticated;

grant all on public.user_category_order to service_role;
