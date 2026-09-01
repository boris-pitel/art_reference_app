-- Restore the client-side keyword workflow after image-table RLS was enabled.
-- A user may create or delete keywords only for images they own. The explicit
-- image ownership check prevents a caller from attaching their keyword row to
-- another user's image even when they supply their own derived user_id.

drop policy if exists "Owners create keywords on their images"
on public.image_keywords;
create policy "Owners create keywords on their images"
on public.image_keywords for insert to authenticated
with check (
  nullif(btrim(user_id), '')::uuid = public.current_app_user_id()
  and exists (
    select 1
    from public.image_assets a
    where a.id = image_id
      and a.user_id = public.current_app_user_id()
  )
);

drop policy if exists "Owners delete keywords from their images"
on public.image_keywords;
create policy "Owners delete keywords from their images"
on public.image_keywords for delete to authenticated
using (
  nullif(btrim(user_id), '')::uuid = public.current_app_user_id()
  and exists (
    select 1
    from public.image_assets a
    where a.id = image_id
      and a.user_id = public.current_app_user_id()
  )
);

grant select, insert, delete on public.image_keywords to authenticated;
revoke update on public.image_keywords from authenticated;

-- The generated bigint primary key uses this sequence during inserts.
revoke all on sequence public.image_keywords_id_seq from anon;
grant usage, select on sequence public.image_keywords_id_seq to authenticated;

