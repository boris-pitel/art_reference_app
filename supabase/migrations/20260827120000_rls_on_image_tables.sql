-- Close the image tables to anyone holding the public key.
--
-- The key shipped in the app is public by design — it is readable in the web
-- bundle — and row level security is what is supposed to stand behind it. On
-- most tables it does. On the oldest ones it never got switched on, so anyone
-- with that key could read every row of image_assets: 253 photographs across
-- nine people, with their email addresses, titles, notes and AI descriptions.
-- image_categories, image_keywords, image_relationships and
-- reference_categories were open the same way, and with row level security off
-- the default grants leave writes open too.
--
-- Ownership here cannot be expressed as auth.uid(). These tables predate
-- Supabase auth in this project and are keyed by a UUID derived from the
-- user's email address, which is a different value from their auth id — for
-- one account, f5e69370-… against e4083465-…. The derivation is reproduced
-- below so a policy can compute it from the caller's own token.

create extension if not exists "uuid-ossp" with schema extensions;

-- The caller's application user id, derived exactly as the client derives it:
-- version 5 in the URL namespace over 'art-reference-user:<lowercased email>'.
-- Verified against the stored ids before this migration was written.
--
-- Null for a caller with no email in their token, which fails every comparison
-- below rather than matching a row — the safe direction.
create or replace function public.current_app_user_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select case
    when nullif(btrim(lower(auth.jwt() ->> 'email')), '') is null then null
    else extensions.uuid_generate_v5(
      extensions.uuid_ns_url(),
      'art-reference-user:' || btrim(lower(auth.jwt() ->> 'email'))
    )
  end
$$;

comment on function public.current_app_user_id() is
  'The application user id for the current caller, derived from their email the same way the client derives it. Used by row level security on the image tables, which predate Supabase auth and are not keyed by auth.uid().';

-- image_assets ---------------------------------------------------------------
-- Nothing in the client reads this table directly; every path goes through an
-- Edge Function holding the service role key, which bypasses row level
-- security entirely. Read access is granted anyway, scoped to the owner, so a
-- future direct query fails safe rather than confusingly. Writes stay with the
-- Edge Functions, which is where the validation and the storage bookkeeping
-- live — a client that could write here directly could orphan files.

alter table public.image_assets enable row level security;

drop policy if exists "Owners read their own images" on public.image_assets;
create policy "Owners read their own images"
on public.image_assets for select to authenticated
using (user_id = public.current_app_user_id());

revoke all on public.image_assets from anon;
revoke insert, update, delete on public.image_assets from authenticated;
grant select on public.image_assets to authenticated;
grant all on public.image_assets to service_role;

-- image_categories -----------------------------------------------------------
-- Read directly by the client, which asks which categories an image belongs
-- to. The table carries no owner of its own, so ownership is the image's.

alter table public.image_categories enable row level security;

drop policy if exists "Owners read their own image categories" on public.image_categories;
create policy "Owners read their own image categories"
on public.image_categories for select to authenticated
using (
  exists (
    select 1
    from public.image_assets a
    where a.id = image_id
      and a.user_id = public.current_app_user_id()
  )
);

revoke all on public.image_categories from anon;
revoke insert, update, delete on public.image_categories from authenticated;
grant select on public.image_categories to authenticated;
grant all on public.image_categories to service_role;

-- image_keywords -------------------------------------------------------------
-- Carries the owner directly, so no join is needed. Its user_id is text here
-- while every other table stores the same value as a uuid, so the comparison
-- is cast rather than left to fail at apply time.

alter table public.image_keywords enable row level security;

drop policy if exists "Owners read their own keywords" on public.image_keywords;
create policy "Owners read their own keywords"
on public.image_keywords for select to authenticated
using (nullif(btrim(user_id), '')::uuid = public.current_app_user_id());

revoke all on public.image_keywords from anon;
revoke insert, update, delete on public.image_keywords from authenticated;
grant select on public.image_keywords to authenticated;
grant all on public.image_keywords to service_role;

-- image_relationships --------------------------------------------------------
-- Sketches and their parent. Ownership follows the parent image: a
-- relationship is visible to whoever owns the reference it hangs from.

alter table public.image_relationships enable row level security;

drop policy if exists "Owners read their own relationships" on public.image_relationships;
create policy "Owners read their own relationships"
on public.image_relationships for select to authenticated
using (
  exists (
    select 1
    from public.image_assets a
    where a.id = parent_image_id
      and a.user_id = public.current_app_user_id()
  )
);

revoke all on public.image_relationships from anon;
revoke insert, update, delete on public.image_relationships from authenticated;
grant select on public.image_relationships to authenticated;
grant all on public.image_relationships to service_role;

-- reference_categories -------------------------------------------------------
-- Partly a shared catalogue and partly personal: four rows are built in, the
-- other sixteen are categories five different people made for themselves. The
-- client already filters on exactly this condition when it reads, and scopes
-- its writes to its own non-builtin rows. None of that was enforced anywhere
-- but in the client, which is to say it was not enforced.

alter table public.reference_categories enable row level security;

drop policy if exists "Everyone reads builtin and their own categories" on public.reference_categories;
create policy "Everyone reads builtin and their own categories"
on public.reference_categories for select to authenticated
using (is_builtin or user_id = public.current_app_user_id());

drop policy if exists "Users create their own categories" on public.reference_categories;
create policy "Users create their own categories"
on public.reference_categories for insert to authenticated
with check (user_id = public.current_app_user_id() and not is_builtin);

drop policy if exists "Users change their own categories" on public.reference_categories;
create policy "Users change their own categories"
on public.reference_categories for update to authenticated
using (user_id = public.current_app_user_id() and not is_builtin)
with check (user_id = public.current_app_user_id() and not is_builtin);

drop policy if exists "Users delete their own categories" on public.reference_categories;
create policy "Users delete their own categories"
on public.reference_categories for delete to authenticated
using (user_id = public.current_app_user_id() and not is_builtin);

revoke all on public.reference_categories from anon;
grant select, insert, update, delete on public.reference_categories to authenticated;
grant all on public.reference_categories to service_role;

-- ai_quota_overview ----------------------------------------------------------
-- A view, and views are not covered by the row level security of the tables
-- beneath them unless asked to be. It reports who has spent how much of their
-- AI allowance, which only the admin console needs, and the admin console
-- holds the service role key.

revoke all on public.ai_quota_overview from anon, authenticated;
grant select on public.ai_quota_overview to service_role;
