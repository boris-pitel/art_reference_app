-- Keep the library intentionally small while preserving images that belonged
-- to removed built-in or user-created categories.
insert into public.reference_categories (
  user_id,
  code,
  display_name,
  thumbnail_asset,
  is_builtin
)
values (null, 'inbox', 'Inbox', null, true)
on conflict (code) where is_builtin = true do update
set display_name = excluded.display_name;

insert into public.image_categories (image_id, category_code)
select distinct image_id, 'inbox'
from public.image_categories
where category_code not in ('portrait', 'landscape', 'still_life', 'inbox')
on conflict (image_id, category_code) do nothing;

delete from public.image_categories
where category_code not in ('portrait', 'landscape', 'still_life', 'inbox');

delete from public.reference_categories
where not (
  is_builtin = true
  and code in ('portrait', 'landscape', 'still_life', 'inbox')
);

create table if not exists public.user_category_cover_overrides (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  category_code text not null check (
    category_code in ('portrait', 'landscape', 'still_life')
  ),
  storage_path text not null,
  updated_at timestamptz not null default now(),
  primary key (auth_user_id, category_code)
);

alter table public.user_category_cover_overrides enable row level security;

create policy "Users read their category cover overrides"
on public.user_category_cover_overrides for select to authenticated
using (auth.uid() = auth_user_id);

create policy "Users create their category cover overrides"
on public.user_category_cover_overrides for insert to authenticated
with check (auth.uid() = auth_user_id);

create policy "Users update their category cover overrides"
on public.user_category_cover_overrides for update to authenticated
using (auth.uid() = auth_user_id)
with check (auth.uid() = auth_user_id);

create policy "Users delete their category cover overrides"
on public.user_category_cover_overrides for delete to authenticated
using (auth.uid() = auth_user_id);

grant select, insert, update, delete
on public.user_category_cover_overrides to authenticated;

grant all on public.user_category_cover_overrides to service_role;
