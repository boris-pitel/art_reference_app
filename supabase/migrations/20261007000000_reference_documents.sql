create table public.reference_documents (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id bigint not null references public.reference_categories(id),
  filename text not null check (length(filename) between 1 and 255),
  file_type text not null check (file_type in ('pdf','txt','rtf','doc','docx')),
  storage_path text not null unique,
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 26214400),
  title text not null,
  notes text not null default '',
  keywords text[] not null default '{}',
  is_favorite boolean not null default false,
  date_added timestamptz not null default now(),
  check (storage_path = user_id::text || '/' || id::text || '.' || file_type)
);
create index reference_documents_category on public.reference_documents(user_id, category_id, date_added desc);
alter table public.reference_documents enable row level security;
create policy "Owners read documents" on public.reference_documents for select to authenticated using (user_id = auth.uid());
create policy "Owners insert documents" on public.reference_documents for insert to authenticated with check (
  user_id = auth.uid() and exists (select 1 from public.reference_categories c where c.id = category_id and (c.is_builtin or c.user_id = public.current_app_user_id()))
);
create policy "Owners update documents" on public.reference_documents for update to authenticated using (user_id = auth.uid()) with check (
  user_id = auth.uid() and exists (select 1 from public.reference_categories c where c.id = category_id and (c.is_builtin or c.user_id = public.current_app_user_id()))
);
create policy "Owners delete documents" on public.reference_documents for delete to authenticated using (user_id = auth.uid());
grant select, insert, update, delete on public.reference_documents to authenticated;
grant all on public.reference_documents to service_role;
revoke all on public.reference_documents from anon;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('reference-documents','reference-documents',false,26214400,
  array['application/pdf','text/plain','application/rtf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document']);
create policy "Owners read document files" on storage.objects for select to authenticated using (bucket_id = 'reference-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Owners upload document files" on storage.objects for insert to authenticated with check (bucket_id = 'reference-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Owners delete document files" on storage.objects for delete to authenticated using (bucket_id = 'reference-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- Deleting a personal category moves its documents to Inbox, like images.
create function public.move_documents_to_inbox() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.reference_documents set category_id = (select id from public.reference_categories where code = 'inbox' and is_builtin limit 1) where category_id = old.id;
  return old;
end;
$$;
create trigger preserve_category_documents before delete on public.reference_categories for each row execute function public.move_documents_to_inbox();
