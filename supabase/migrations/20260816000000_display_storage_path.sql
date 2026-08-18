alter table public.image_assets
  add column if not exists display_storage_path text;
