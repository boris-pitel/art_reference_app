alter table public.image_assets
  add column if not exists original_filename text,
  add column if not exists capture_timestamp timestamptz,
  add column if not exists photo_metadata jsonb;
