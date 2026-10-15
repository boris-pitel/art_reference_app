"""Reproducibly extract Dakota's scanned Unison chart (no image enhancement)."""
import colorsys
import hashlib
import json
import math
from pathlib import Path
from statistics import median

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/unison-catalogue'
SOURCE = Path('C:/Users/boris/OneDrive/Documents')

def codes(prefix, first, last):
    return [f'{prefix}{i}' for i in range(first, last + 1)]

PAGES = [
    ('img20261015_12283543.jpg', (991, 2048), (50, 285, 100, 134), codes('A',1,54)+codes('BE',1,26)),
    ('img20261015_12415555.jpg', (1032, 2048), (80, 290, 100, 135), codes('BE',27,36)+codes('BG',1,18)+codes('BGE',1,18)+codes('BV',1,18)+codes('DARK',1,16)),
    ('img20261015_12460457.jpg', (996, 2048), (44, 290, 100, 135), codes('DARK',17,24)+codes('CB',1,2)+codes('GRN',1,36)+codes('GREY',1,34)),
    ('img20261015_12532890.jpg', (1097, 2048), (50, 392, 111, 150), codes('GREY',35,36)+codes('LT',1,18)+codes('NE',1,18)+codes('OB',1,12)+codes('ORG',1,6)+codes('P',1,12)+codes('RED',1,12)),
    ('img20261015_12563362.jpg', (999, 2048), (43, 291, 101, 136), codes('RED',13,18)+codes('RE',1,18)+codes('Y',1,18)+codes('YGE',1,18)),
]

def lab(rgb):
    v = [c/255 for c in rgb]
    r,g,b = [c/12.92 if c <= .04045 else ((c+.055)/1.055)**2.4 for c in v]
    x=(.4124564*r+.3575761*g+.1804375*b)/.95047
    y=.2126729*r+.7151522*g+.0721750*b
    z=(.0193339*r+.1191920*g+.9503041*b)/1.08883
    f=lambda t: t**(1/3) if t>(6/29)**3 else t/(3*(6/29)**2)+4/29
    fx,fy,fz=map(f,(x,y,z))
    return [round(116*fy-16,4),round(500*(fx-fy),4),round(200*(fy-fz),4)]

def name(rgb):
    h,l,s=colorsys.rgb_to_hls(*(c/255 for c in rgb)); h*=360
    if s<.10:
        return 'near black' if l<.12 else 'dark grey' if l<.35 else 'grey' if l<.7 else 'pale grey' if l<.94 else 'near white'
    hue=next(n for end,n in [(15,'red'),(40,'orange'),(65,'yellow'),(90,'yellow-green'),(165,'green'),(195,'blue-green'),(255,'blue'),(290,'violet'),(330,'purple'),(361,'red')] if h<end)
    if hue in ('orange','yellow') and l<.62: hue='brown' if h<45 else 'olive'
    if hue=='red' and l>.72: hue='pink'
    return ('very dark ' if l<.15 else 'dark ' if l<.32 else 'pale ' if l>.78 else 'light ' if l>.64 else '')+('muted ' if s<.30 else '')+hue

def main():
    for folder in ('swatches','sources'): (OUT/folder).mkdir(parents=True,exist_ok=True)
    rows=[]; sources=[]
    sheet=Image.new('RGB',(1000,math.ceil(380/10)*106),'white'); draw=ImageDraw.Draw(sheet)
    for page,(filename,display,grid,labels) in enumerate(PAGES,1):
        raw=(SOURCE/filename).read_bytes(); (OUT/'sources'/filename).write_bytes(raw)
        im=Image.open(SOURCE/filename).convert('RGB'); sx,sy=im.width/display[0],im.height/display[1]
        sources.append(dict(page=page,filename=filename,sha256=hashlib.sha256(raw).hexdigest(),width=im.width,height=im.height))
        x0,y0,dx,dy=grid
        for i,code in enumerate(labels):
            x=x0+(i%10)*dx; y=y0+(i//10)*dy
            # Exclude dotted frames and code text; preserve actual pigment texture.
            box=tuple(round(v) for v in ((x-dx*.36)*sx,(y-dy*.32)*sy,(x+dx*.36)*sx,(y+dy*.32)*sy))
            crop=im.crop(box); rel=f'swatches/{code}.png'; crop.save(OUT/rel)
            sample=im.crop(tuple(round(v) for v in ((x-dx*.13)*sx,(y-dy*.15)*sy,(x+dx*.13)*sx,(y+dy*.15)*sy)))
            pixels=list(sample.getdata()); rgb=[round(median(c)) for c in zip(*pixels)]
            row=dict(brand='Unison',code=code,printed_code='YGR14' if code=='YGE14' else code,display_name=name(rgb),source_page=page,swatch_path=rel,crop_box=list(box),rgb_r=rgb[0],rgb_g=rgb[1],rgb_b=rgb[2],lab_l=lab(rgb)[0],lab_a=lab(rgb)[1],lab_b=lab(rgb)[2],verification_status='label_needs_review' if code=='YGE14' else 'unreviewed',notes='Chart prints YGR14; provisional code YGE14 inferred from sequence.' if code=='YGE14' else '')
            rows.append(row); n=len(rows)-1; thumb=crop.copy(); thumb.thumbnail((86,78)); xx=(n%10)*100; yy=(n//10)*106; sheet.paste(thumb,(xx,yy)); draw.text((xx,yy+80),code,fill='black')
    assert len(rows)==380 and len({r['code'] for r in rows})==380
    (OUT/'catalogue.json').write_text(json.dumps(dict(sources=sources,swatches=rows),indent=2))
    sheet.save(OUT/'contact-sheet.jpg',quality=90)
    print(f'Extracted {len(rows)} unique swatches; originals preserved. RGB interpreted as sRGB; Lab D65. All names approximate.')

if __name__=='__main__': main()
