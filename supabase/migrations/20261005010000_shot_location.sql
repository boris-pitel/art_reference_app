alter table public.image_assets
  add column if not exists shot_location text;

alter table public.image_assets
  add constraint image_assets_shot_location_length
  check (shot_location is null or length(shot_location) <= 200);
