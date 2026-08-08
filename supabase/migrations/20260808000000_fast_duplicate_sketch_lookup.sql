create index if not exists image_relationships_child_parent_index
  on public.image_relationships (child_image_id, parent_image_id);
