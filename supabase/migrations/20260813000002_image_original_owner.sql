alter table public.image_assets
  add column if not exists original_owner_name text;

create index if not exists image_assets_original_owner_name_idx
on public.image_assets (lower(original_owner_name))
where original_owner_name is not null;
