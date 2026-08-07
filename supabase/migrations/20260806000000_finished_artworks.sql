alter table public.image_assets
  add column if not exists is_finished_artwork boolean not null default false;

create index if not exists image_assets_finished_artwork_user_idx
  on public.image_assets (user_id, date_added desc)
  where is_finished_artwork = true;
