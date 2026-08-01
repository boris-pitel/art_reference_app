-- Exact non-user configuration rows exported from project
-- bbcgcrbvxmertipdjczu on 2026-08-01. User images, keywords, custom
-- categories, authentication users, and Storage object rows are excluded.

insert into public.reference_categories
  (id, user_id, code, display_name, thumbnail_asset, is_builtin, created_at)
values
  (1, null, 'portrait', 'Portraits', 'assets/category_thumbnails/portraits.jpg', true, '2026-07-30 08:39:41.071743+00'),
  (2, null, 'landscape', 'Landscapes', 'assets/category_thumbnails/landscapes.jpg', true, '2026-07-30 08:39:41.071743+00'),
  (3, null, 'architecture', 'Architecture', 'assets/category_thumbnails/architecture.jpg', true, '2026-07-30 08:39:41.071743+00'),
  (4, null, 'still_life', 'Still Life', 'assets/category_thumbnails/stilllife.jpg', true, '2026-07-30 08:39:41.071743+00'),
  (5, null, 'abstract', 'Abstract', 'assets/category_thumbnails/abstract.jpg', true, '2026-07-30 08:39:41.071743+00'),
  (6, null, 'icon', 'Icon', 'assets/category_thumbnails/icon.jpg', true, '2026-07-30 08:39:41.071743+00')
on conflict (id) do nothing;

select setval(
  pg_get_serial_sequence('public.reference_categories', 'id'),
  greatest((select coalesce(max(id), 1) from public.reference_categories), 6),
  true
);

insert into storage.buckets
  (id, name, owner, created_at, updated_at, public, avif_autodetection,
   file_size_limit, allowed_mime_types, owner_id, type)
values
  ('art-images', 'art-images', null, '2026-07-20 21:23:03.854474+00', '2026-07-20 21:23:03.854474+00', false, false, null, null, null, 'STANDARD'),
  ('reference-images', 'reference-images', null, '2026-07-25 13:47:10.205814+00', '2026-07-25 13:47:10.205814+00', false, false, null, null, null, 'STANDARD')
on conflict (id) do nothing;
