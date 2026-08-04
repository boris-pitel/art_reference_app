-- Administrative cleanup used only by the local Painter Reference admin CLI.
-- The function is intentionally executable only by service_role.
create or replace function public.admin_delete_user_data(
  target_user_id uuid,
  target_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_images integer := 0;
  deleted_categories integer := 0;
begin
  if target_user_id is null then
    raise exception 'target_user_id is required';
  end if;

  if target_email is null or length(trim(target_email)) = 0 then
    raise exception 'target_email is required';
  end if;

  delete from public.reference_categories
  where user_id = target_user_id
    and is_builtin = false;
  get diagnostics deleted_categories = row_count;

  -- Dependent image_categories, image_keywords, and image_relationships
  -- are deleted by the existing ON DELETE CASCADE constraints.
  delete from public.image_assets
  where user_id = target_user_id
     or lower(trim(user_email)) = lower(trim(target_email));
  get diagnostics deleted_images = row_count;

  return jsonb_build_object(
    'deleted_images', deleted_images,
    'deleted_categories', deleted_categories
  );
end;
$$;

revoke all on function public.admin_delete_user_data(uuid, text)
from public, anon, authenticated;

grant execute on function public.admin_delete_user_data(uuid, text)
to service_role;

comment on function public.admin_delete_user_data(uuid, text) is
  'Permanently removes Painter Reference database rows owned by one user. Administrative service-role use only.';