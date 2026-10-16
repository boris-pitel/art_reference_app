"""Map the browser-extracted Dakota product rows to our 380 scanned codes."""
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/unison-catalogue'
source='https://dakotapastels.com/products/Soft-Unison-Individual'
products=json.loads((ROOT/'tool/catalogue/data/dakota-names-2026-10-16.json').read_text())
catalogue=json.loads((OUT/'catalogue.json').read_text())
mapped={}
for product in products:
    match=re.fullmatch(r'UNS([A-Z]+)(\d+)',product['sku'])
    assert match,product
    family,number=match.groups()
    code={'GREEN':'GRN','ORANGE':'ORG'}.get(family,family)+str(int(number))
    assert code not in mapped,code
    mapped[code]=product
codes={r['code'] for r in catalogue['swatches']}
assert len(mapped)==380 and set(mapped)==codes,(codes-set(mapped),set(mapped)-codes)
q=lambda s: "'"+str(s).replace("'","''")+"'"
sql='''-- Replace generated display descriptions with exact Dakota listing names.
-- Keep the old approximation separately; RGB/Lab and scan data are unchanged.
alter table public.pastel_swatches add column approximate_name text;
alter table public.pastel_swatches add column name_source_url text;
alter table public.pastel_swatches add column retailer_sku text;
update public.pastel_swatches set approximate_name=display_name where brand='Unison';
'''
sql+='with names(code, product_name, sku) as (values\n'
sql+=',\n'.join('('+','.join(map(q,(code,p['name'],p['sku'])))+')' for code,p in mapped.items())
sql+=f''')
update public.pastel_swatches s
set display_name=n.product_name, retailer_sku=n.sku,
name_source_url={q(source)}, name_method='Exact Dakota Art Pastels product listing, extracted 2026-10-16'
from names n where s.brand='Unison' and s.code=n.code;
update public.pastel_swatches
set verification_status='unreviewed',
notes='Chart prints YGR14. Dakota product listing confirms code YGE14 (UNSYGE14). Scan and color sample still await review.'
where brand='Unison' and code='YGE14';
do $$ begin
  if (select count(*) from public.pastel_swatches where brand='Unison' and retailer_sku is not null and name_source_url is not null) <> 380 then
    raise exception 'Dakota names import must cover all 380 Unison swatches';
  end if;
end $$;
'''
(ROOT/'supabase/migrations/20261016000000_dakota_unison_names.sql').write_text(sql)
# This local snapshot drives the read-only review page, too.
for row in catalogue['swatches']:
    p=mapped[row['code']]
    row.setdefault('approximate_name',row['display_name'])
    row.update(display_name=p['name'],retailer_sku=p['sku'],name_source_url=source,
               name_method='Exact Dakota Art Pastels product listing, extracted 2026-10-16')
    if row['code']=='YGE14':
        row['verification_status']='unreviewed'
        row['notes']='Chart prints YGR14; Dakota confirms YGE14 (UNSYGE14).'
(OUT/'catalogue.json').write_text(json.dumps(catalogue,indent=2))
print('Matched all 380 codes uniquely; zero missing or extra names. Migration prepared.')
