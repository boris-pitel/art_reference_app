"""Generate the additive catalogue migration from the reviewed extraction."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
data=json.loads((ROOT/'output/unison-catalogue/catalogue.json').read_text())
sql='''-- Dakota hand-applied Unison chart, scanned 2026-10-15.
-- Descriptive names and sampled colors are approximate, not manufacturer specifications.
create table public.pastel_catalogue_sources (
  id bigint generated always as identity primary key,
  brand text not null,
  page_number integer not null check (page_number > 0),
  filename text not null,
  storage_path text not null unique,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  width integer not null check (width > 0),
  height integer not null check (height > 0),
  unique(brand, page_number)
);
create table public.pastel_swatches (
  id bigint generated always as identity primary key,
  brand text not null,
  code text not null,
  printed_code text not null,
  display_name text not null,
  source_id bigint not null references public.pastel_catalogue_sources(id),
  swatch_path text not null unique,
  crop_box integer[] not null check (array_length(crop_box, 1) = 4),
  rgb_r smallint not null check (rgb_r between 0 and 255),
  rgb_g smallint not null check (rgb_g between 0 and 255),
  rgb_b smallint not null check (rgb_b between 0 and 255),
  lab_l double precision not null check (lab_l between 0 and 100),
  lab_a double precision not null check (lab_a between -160 and 160),
  lab_b double precision not null check (lab_b between -160 and 160),
  color_method text not null default 'central patch channel median; assumed sRGB; Lab D65; uncalibrated',
  name_method text not null default 'approximate generated description; not official Unison name',
  verification_status text not null check (verification_status in ('unreviewed','label_needs_review','verified')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique(brand, code)
);
alter table public.pastel_catalogue_sources enable row level security;
alter table public.pastel_swatches enable row level security;
revoke all on public.pastel_catalogue_sources, public.pastel_swatches from anon, authenticated;
grant select on public.pastel_catalogue_sources, public.pastel_swatches to authenticated;
grant all on public.pastel_catalogue_sources, public.pastel_swatches to service_role;
create policy catalogue_sources_read on public.pastel_catalogue_sources for select to authenticated using (true);
create policy pastel_swatches_read on public.pastel_swatches for select to authenticated using (true);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('pastel-catalogue','pastel-catalogue',false,16777216,array['image/jpeg','image/png']);
create policy pastel_catalogue_read on storage.objects for select to authenticated
using (bucket_id = 'pastel-catalogue');
-- Writes are reserved for trusted administrative imports, never client credentials.
'''
q=lambda s: "'"+str(s).replace("'","''")+"'"
for s in data['sources']:
    sql+='insert into public.pastel_catalogue_sources(brand,page_number,filename,storage_path,sha256,width,height) values ('+','.join([q('Unison'),str(s['page']),q(s['filename']),q('sources/'+s['filename']),q(s['sha256']),str(s['width']),str(s['height'])])+');\n'
for r in data['swatches']:
    cols=['brand','code','printed_code','display_name','source_id','swatch_path','crop_box','rgb_r','rgb_g','rgb_b','lab_l','lab_a','lab_b','verification_status','notes']
    vals=[q(r[k]) for k in cols[:4]]
    vals += [f"(select id from public.pastel_catalogue_sources where brand='Unison' and page_number={r['source_page']})",q(r['swatch_path']),'array['+','.join(map(str,r['crop_box']))+']']
    vals += [str(r[k]) for k in cols[7:13]]+[q(r[k]) for k in cols[13:]]
    sql+='insert into public.pastel_swatches('+','.join(cols)+') values ('+','.join(vals)+');\n'
sql+="do $$ begin if (select count(*) from public.pastel_swatches where brand='Unison') <> 380 then raise exception 'Unison import count mismatch'; end if; end $$;\n"
(ROOT/'supabase/migrations/20261015000000_unison_pastel_catalogue.sql').write_text(sql)
print('Generated schema and 380 rows, with source hashes and private Storage bucket.')
