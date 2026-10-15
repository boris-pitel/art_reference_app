"""Build a self-contained, read-only review of the imported catalogue."""
import base64
import io
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/unison-catalogue'
data = json.loads((OUT / 'catalogue.json').read_text())
for row in data['swatches']:
    image = Image.open(OUT / row['swatch_path']).convert('RGB')
    image.thumbnail((220, 220))
    stream = io.BytesIO()
    image.save(stream, format='PNG')
    row['preview'] = 'data:image/png;base64,' + base64.b64encode(stream.getvalue()).decode()

html = '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Unison catalogue review</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f4f2ee;color:#262b29;font:16px system-ui,sans-serif}header{padding:30px max(24px,calc((100vw - 1300px)/2));background:#183f38;color:white}h1{margin:6px 0 10px;font-size:32px}header p{max-width:850px;line-height:1.6;color:#e0ece7}main{max-width:1350px;margin:auto;padding:24px}nav{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:18px}button,input{font:inherit;border:1px solid #aabbb3;border-radius:8px;padding:10px 16px;background:white;color:#183f38}button{cursor:pointer}button[aria-pressed=true]{background:#183f38;color:white}input{flex:1;min-width:200px}#count{margin:16px 0;color:#56635d}#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(265px,1fr));gap:18px}.card{background:white;border:1px solid #d8dfd9;border-radius:12px;padding:18px}.top{display:flex;justify-content:space-between;align-items:baseline}.code{font-size:23px;margin:0}.page{font-size:13px;color:#66766e}.comparison{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}.comparison img,.patch{width:100%;height:135px;object-fit:contain;background:#fff;border:1px solid #ddd;border-radius:5px}.caption{font-size:12px;color:#52665b;margin:5px 0}.name{font-weight:600;margin:14px 0 8px}.values{font:12px ui-monospace,monospace;color:#5e6d64;line-height:1.7}.flag{background:#fff1d1;color:#744c00;padding:8px;border-radius:5px;font-size:13px}.hint{padding:16px;background:#e6eee8;border-radius:8px;line-height:1.6}a{color:#18634a}footer{padding:24px;color:#67736c}button:focus-visible,input:focus-visible{outline:3px solid #e4ac43;outline-offset:2px}
</style>
<header><small>DAKOTA SCANS · UNISON · 380 SWATCHES</small><h1>Review the colour catalogue</h1><p>Compare the actual scan crop with its representative sampled colour. Names are approximate descriptions, not official Unison names. This page is read-only and makes no database changes.</p></header>
<main><nav aria-label="Choose review group"><button data-page="starter" aria-pressed="true">Start with 20</button><button data-page="all">All 380</button><button data-page="1">Page 1</button><button data-page="2">Page 2</button><button data-page="3">Page 3</button><button data-page="4">Page 4</button><button data-page="5">Page 5</button></nav>
<nav><input id="search" aria-label="Search code or descriptive name" placeholder="Search code or name, e.g. A1 or blue"><button id="flagged">Check uncertain label</button></nav>
<div class="hint">For each swatch: <strong>1.</strong> Is the code correct? <strong>2.</strong> Does the solid patch represent the pigment? <strong>3.</strong> Is the name reasonable? Send corrections as “code → correction.” Colours are uncalibrated scan estimates. This is the import snapshot, not a live database editor.</div>
<div id="count" role="status"></div><section id="grid" aria-label="Swatch comparison cards"></section>
<footer>Source scans preserved without colour enhancement. RGB assumes sRGB; Lab uses D65. All entries await review; YGE14 additionally has an uncertain printed label.</footer></main>
<script>
const rows=__DATA__;
const starter=new Set(['A1','A14','A30','A37','BE7','BG6','BG13','BV12','DARK16','GRN12','GRN25','GREY6','GREY28','LT1','LT11','NE7','OB7','RED7','Y12','YGE14']);
let group='starter',uncertain=false;
const grid=document.getElementById('grid'),search=document.getElementById('search');
function render(){
 const query=search.value.trim().toLowerCase();
 const selected=rows.filter(r=>(group==='all'||group==='starter'&&starter.has(r.code)||String(r.source_page)===group)&&(!uncertain||r.verification_status==='label_needs_review')&&(`${r.code} ${r.printed_code} ${r.display_name}`.toLowerCase().includes(query)));
 document.getElementById('count').textContent=`${selected.length} swatches shown · ${uncertain?'uncertain label':group==='starter'?'20 varied examples':group==='all'?'complete catalogue':'source page '+group}`;
 grid.replaceChildren();
 for(const r of selected){const article=document.createElement('article');article.className='card';
 article.innerHTML=`<div class="top"><h2 class="code"></h2><span class="page">Source page ${r.source_page}</span></div><div class="comparison"><div><img loading="lazy" alt=""><p class="caption">Scanned pigment</p></div><div><div class="patch"></div><p class="caption">Sampled colour</p></div></div><p class="name"></p><div class="values"></div>`;
 article.querySelector('.code').textContent=r.code;article.querySelector('img').src=r.preview;article.querySelector('img').alt=`Original scanned ${r.code} swatch`;
 article.querySelector('.patch').style.backgroundColor=`rgb(${r.rgb_r},${r.rgb_g},${r.rgb_b})`;
 article.querySelector('.name').textContent=r.display_name;article.querySelector('.values').textContent=`RGB ${r.rgb_r}, ${r.rgb_g}, ${r.rgb_b} · Lab ${r.lab_l.toFixed(1)}, ${r.lab_a.toFixed(1)}, ${r.lab_b.toFixed(1)}`;
 if(r.notes){const note=document.createElement('p');note.className='flag';note.textContent=r.notes;article.append(note)}grid.append(article)}
 document.querySelectorAll('[data-page]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.page===group&&!uncertain)));
 document.getElementById('flagged').setAttribute('aria-pressed',String(uncertain));
}
document.querySelectorAll('[data-page]').forEach(b=>b.onclick=()=>{group=b.dataset.page;uncertain=false;search.value='';render()});
search.oninput=render;document.getElementById('flagged').onclick=()=>{group='all';uncertain=true;search.value='';render()};render();
</script></html>'''.replace('__DATA__',json.dumps(data['swatches']).replace('</','<\\/'))
(OUT/'review.html').write_text(html,encoding='utf-8')
print('Created self-contained review.html with 380 embedded previews and 20 starter examples.')
