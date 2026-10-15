-- Matching experiment: trust the server-managed claim, never user_metadata.
create function public.admin_unison_catalogue()
returns setof public.pastel_swatches
language plpgsql stable security invoker set search_path = '' as $$
begin
  if coalesce(auth.jwt()->'app_metadata'->>'is_admin','false') <> 'true' then
    raise exception 'Administrator access required' using errcode = '42501';
  end if;
  return query select * from public.pastel_swatches where brand = 'Unison' order by id;
end;
$$;
revoke all on function public.admin_unison_catalogue() from public, anon;
grant execute on function public.admin_unison_catalogue() to authenticated;
