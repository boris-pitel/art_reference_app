-- A reference keeps its original asset; an associated image can be displayed
-- as its front image without changing category membership or metadata.
alter table public.image_assets
  add column if not exists featured_child_image_id uuid
  references public.image_assets(id) on delete set null;

create index if not exists image_assets_featured_child_image_id_idx
  on public.image_assets(featured_child_image_id)
  where featured_child_image_id is not null;
