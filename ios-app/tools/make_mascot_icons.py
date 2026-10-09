#!/usr/bin/env python3
"""Dawnwick app-icon concepts, round 2: other mascots (cat, fox, owl, penguin, tiger), determined / no-snooze.
Hand-built SVG, tonal lighting, rendered by headless Chrome.
Run:  python3 tools/make_mascot_icons.py   → design/ember-sky/icon/concepts-mascots/{svg,png}
"""
import subprocess, pathlib
from make_icon_concepts import DEFS, CHROME, EMBER, EMBER_HI, EMBER_LO, GOLD, GOLD_HI, GOLD_LO, INK, CREAM, PALE

ROOT = pathlib.Path(__file__).resolve().parents[3] / "design" / "ember-sky" / "icon" / "concepts-mascots"
SVG_DIR, OUT = ROOT / "svg", ROOT / "png"

TAWNY, TAWNY_HI, TAWNY_LO = "#C86A26", "#E5893D", "#8E3F0E"
DARK, DARK_HI, DARK_LO = "#23263A", "#484C68", "#101120"
PINK = "#F29A73"
BROWN = "#4A2410"

DEFS2 = f"""
<defs>
  <radialGradient id="creamLight" cx="0.36" cy="0.26" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="0.5" stop-color="{CREAM}"/><stop offset="1" stop-color="#E6D2AE"/></radialGradient>
  <radialGradient id="tawnyLight" cx="0.36" cy="0.26" r="0.8"><stop offset="0" stop-color="{TAWNY_HI}"/><stop offset="0.5" stop-color="{TAWNY}"/><stop offset="1" stop-color="{TAWNY_LO}"/></radialGradient>
  <radialGradient id="darkLight" cx="0.36" cy="0.26" r="0.8"><stop offset="0" stop-color="{DARK_HI}"/><stop offset="0.5" stop-color="{DARK}"/><stop offset="1" stop-color="{DARK_LO}"/></radialGradient>
  <linearGradient id="shadeBig" gradientUnits="userSpaceOnUse" x1="0" y1="-120" x2="0" y2="110">
    <stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.30"/></linearGradient>
</defs>"""

def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{DEFS}{DEFS2}\n'
            f'<rect width="1024" height="1024" fill="url(#plate)"/>\n{body}\n</svg>\n')

def glow(cx=0, cy=0, rx=110, ry=120, op=0.45):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{GOLD}" opacity="{op}" filter="url(#bloom)"/>'

def contact(y=100, rx=70, op=0.45):
    return f'<ellipse cx="0" cy="{y}" rx="{rx}" ry="9" fill="#000" opacity="{op}" filter="url(#contact)"/>'

def specular(cx, cy, rx, ry, clip):
    return (f'<g clip-path="url(#{clip})"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate(22 {cx} {cy})" '
            f'fill="{PALE}" opacity="0.2" filter="url(#soft)"/></g>')

_defs = []
def lidded(cx, cy, rx, ry, side, inner, slant=0.42, key=""):
    """Eye with a slanted upper lid (determined). side=-1 left eye. `inner` = svg drawn inside the clip (iris, pupil, highlight)."""
    cid = f"lid{key}{'L' if side < 0 else 'R'}"
    top_out, top_in = cy - ry - 2, cy - ry + ry * 2 * slant
    xo, xi = cx - side * -1 * (rx + 3) * -1, 0  # placeholder to keep math explicit below
    x_outer = cx - (rx + 3) if side < 0 else cx + (rx + 3)
    x_inner = cx + (rx + 3) if side < 0 else cx - (rx + 3)
    pts = f"{x_outer},{top_out} {x_inner},{top_in} {x_inner},{cy + ry + 4} {x_outer},{cy + ry + 4}"
    _defs.append(f'<clipPath id="{cid}"><polygon points="{pts}"/></clipPath>')
    return f'<g clip-path="url(#{cid})">{inner}</g>'

def mirror(s):
    return f'<g transform="scale(-1 1)">{s}</g>'

def band(y, h, color, clip, dot=None, knot_x=None, tail_color=None):
    s = f'<g clip-path="url(#{clip})"><rect x="-140" y="{y}" width="280" height="{h}" fill="{color}"/>' \
        f'<rect x="-140" y="{y + h - 3}" width="280" height="3" fill="#000" opacity="0.16"/></g>'
    if dot: s += f'<circle cx="{dot[0]}" cy="{y + h / 2}" r="{dot[1]}" fill="{dot[2]}"/>'
    if knot_x is not None:
        tc = tail_color or color; cy = y + h / 2
        s += (f'<path d="M{knot_x},{cy - 4} C{knot_x + 12},{cy - 14} {knot_x + 24},{cy - 24} {knot_x + 40},{cy - 28} '
              f'C{knot_x + 34},{cy - 20} {knot_x + 31},{cy - 14} {knot_x + 30},{cy - 6} C{knot_x + 22},{cy - 8} {knot_x + 14},{cy - 6} {knot_x + 6},{cy - 1} Z" fill="{tc}"/>'
              f'<path d="M{knot_x + 2},{cy + 4} C{knot_x + 12},{cy + 4} {knot_x + 24},{cy + 10} {knot_x + 36},{cy + 22} '
              f'C{knot_x + 28},{cy + 20} {knot_x + 21},{cy + 21} {knot_x + 15},{cy + 26} C{knot_x + 12},{cy + 16} {knot_x + 8},{cy + 10} {knot_x + 2},{cy + 8} Z" fill="{tc}"/>'
              f'<circle cx="{knot_x + 1}" cy="{cy}" r="{h * 0.42}" fill="{tc}"/><circle cx="{knot_x + 1}" cy="{cy}" r="{h * 0.42}" fill="#000" opacity="0.08"/>')
    return s

# ---------- 1 · Hero cat (cream, ember headband, raised paw) ----------
CAT_HEAD = "M-98,0 C-98,-50 -54,-76 0,-76 C54,-76 98,-50 98,0 C98,48 54,80 0,80 C-54,80 -98,48 -98,0 Z"
_defs.append(f'<clipPath id="catHead"><path d="{CAT_HEAD}"/></clipPath>')
ear = f'<path d="M-86,-28 L-80,-114 L-22,-66 Z" fill="url(#creamLight)"/><path d="M-76,-42 L-72,-96 L-38,-66 Z" fill="{PINK}"/>'
cat_eye = lambda side: lidded(side * 36, 8, 15, 18, side,
    f'<ellipse cx="{side*36}" cy="8" rx="15" ry="18" fill="url(#coreLight)"/><ellipse cx="{side*36}" cy="9" rx="6" ry="15" fill="{INK}"/>'
    f'<circle cx="{side*36 + 5}" cy="0" r="3.5" fill="{PALE}"/>', key="cat")
paw = (f'<g transform="translate(92 56)"><ellipse cx="0" cy="12" rx="27" ry="24" fill="url(#creamLight)"/>'
       f'<circle cx="-16" cy="-10" r="10" fill="url(#creamLight)"/><circle cx="1" cy="-15" r="10" fill="url(#creamLight)"/><circle cx="18" cy="-9" r="10" fill="url(#creamLight)"/>'
       f'<ellipse cx="0" cy="16" rx="12" ry="9" fill="{PINK}"/><circle cx="-14" cy="-6" r="4" fill="{PINK}"/><circle cx="1" cy="-10" r="4" fill="{PINK}"/><circle cx="16" cy="-5" r="4" fill="{PINK}"/></g>')
c1 = f'''<g transform="translate(512 548) scale(3.7)">
  {glow(cy=-6)}{contact(y=94, rx=84)}
  {ear}{mirror(ear)}
  <path d="{CAT_HEAD}" fill="url(#creamLight)"/><path d="{CAT_HEAD}" fill="url(#shadeBig)"/>
  {specular(-40, -46, 16, 30, "catHead")}
  {band(-52, 20, EMBER, "catHead", knot_x=90, tail_color=EMBER)}
  {cat_eye(-1)}{cat_eye(1)}
  <path d="M-7,34 L7,34 L0,44 Z" fill="{PINK}" stroke="{PINK}" stroke-width="3" stroke-linejoin="round"/>
  <path d="M0,44 C-2,52 -9,54 -16,50 M0,44 C2,52 9,54 16,50" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>
  <g stroke="{INK}" stroke-width="2.4" stroke-linecap="round" opacity="0.35"><path d="M-54,40 L-104,34 M-54,50 L-104,56 M54,40 L104,34 M54,50 L104,56"/></g>
  {paw}
</g>'''

# ---------- 2 · Focus fox (ember, cream headband) ----------
FOX_HEAD = "M-96,-14 C-96,-56 -52,-76 0,-76 C52,-76 96,-56 96,-14 C96,26 52,76 0,90 C-52,76 -96,26 -96,-14 Z"
_defs.append(f'<clipPath id="foxHead"><path d="{FOX_HEAD}"/></clipPath>')
fox_ear = f'<path d="M-90,-44 L-76,-130 L-22,-70 Z" fill="url(#rimLight)"/><path d="M-78,-58 L-72,-108 L-42,-70 Z" fill="{BROWN}"/>'
FOX_MASK = "M-72,-2 C-72,44 -32,88 0,90 C32,88 72,44 72,-2 C58,20 42,28 26,24 C16,32 -16,32 -26,24 C-42,28 -58,20 -72,-2 Z"
fox_eye = lambda side: lidded(side * 38, -2, 13, 16, side,
    f'<ellipse cx="{side*38}" cy="-2" rx="13" ry="16" fill="{INK}"/><circle cx="{side*38 + 4}" cy="-9" r="3.6" fill="{PALE}"/>', key="fox")
c2 = f'''<g transform="translate(512 548) scale(3.6)">
  {glow(cy=-6)}{contact(y=98, rx=84)}
  {fox_ear}{mirror(fox_ear)}
  <path d="{FOX_HEAD}" fill="url(#rimLight)"/><path d="{FOX_HEAD}" fill="url(#shadeBig)"/>
  <path d="{FOX_MASK}" fill="url(#creamLight)"/>
  {specular(-44, -44, 16, 28, "foxHead")}
  {band(-58, 18, CREAM, "foxHead", dot=(-4, 5, EMBER), knot_x=88, tail_color=CREAM)}
  {fox_eye(-1)}{fox_eye(1)}
  <path d="M-8,50 L8,50 L0,60 Z" fill="{INK}" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>
</g>'''

# ---------- 3 · Owl (tawny, fierce brows) ----------
OWL_BODY = "M-84,-30 C-84,-102 84,-102 84,-30 C84,50 62,104 0,104 C-62,104 -84,50 -84,-30 Z"
_defs.append(f'<clipPath id="owlBody"><path d="{OWL_BODY}"/></clipPath>')
tuft = f'<path d="M-74,-70 L-92,-118 L-38,-90 Z" fill="url(#tawnyLight)"/>'
owl_eye = lambda side: (f'<circle cx="{side*36}" cy="-12" r="24" fill="url(#coreLight)"/><circle cx="{side*36 - side*3}" cy="-10" r="12" fill="{INK}"/>'
                        f'<circle cx="{side*36 - side*1}" cy="-16" r="4" fill="{PALE}"/>')
c3 = f'''<g transform="translate(512 540) scale(3.5)">
  {glow(cy=0, rx=120, ry=130)}{contact(y=110, rx=80)}
  {tuft}{mirror(tuft)}
  <path d="{OWL_BODY}" fill="url(#tawnyLight)"/><path d="{OWL_BODY}" fill="url(#shadeBig)"/>
  <g clip-path="url(#owlBody)"><ellipse cx="-78" cy="40" rx="20" ry="52" fill="{TAWNY_LO}" opacity="0.6"/><ellipse cx="78" cy="40" rx="20" ry="52" fill="{TAWNY_LO}" opacity="0.6"/></g>
  <ellipse cx="0" cy="62" rx="44" ry="34" fill="{TAWNY_HI}"/>
  <g fill="none" stroke="{TAWNY_LO}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round" opacity="0.7">
    <path d="M-22,52 L-12,60 L-2,52 M2,52 L12,60 L22,52 M-12,68 L-2,76 L8,68"/></g>
  <circle cx="-36" cy="-12" r="44" fill="url(#creamLight)"/><circle cx="36" cy="-12" r="44" fill="url(#creamLight)"/>
  {specular(-56, -60, 14, 26, "owlBody")}
  {owl_eye(-1)}{owl_eye(1)}
  <path d="M-68,-54 L-12,-36 M68,-54 L12,-36" fill="none" stroke="{BROWN}" stroke-width="10" stroke-linecap="round"/>
  <path d="M-9,4 L9,4 L0,26 Z" fill="{GOLD}" stroke="{GOLD_LO}" stroke-width="3" stroke-linejoin="round"/>
  <ellipse cx="-24" cy="104" rx="14" ry="7" fill="{GOLD}"/><ellipse cx="24" cy="104" rx="14" ry="7" fill="{GOLD}"/>
</g>'''

# ---------- 4 · Penguin (dark, ember scarf, awake) ----------
PEN_BODY = "M-78,-36 C-78,-106 78,-106 78,-36 C78,44 62,100 0,100 C-62,100 -78,44 -78,-36 Z"
_defs.append(f'<clipPath id="penBody"><path d="{PEN_BODY}"/></clipPath>')
FACE = "M-54,-30 C-54,-74 54,-74 54,-30 C54,4 32,30 0,34 C-32,30 -54,4 -54,-30 Z"
pen_eye = lambda side: f'<circle cx="{side*22}" cy="-26" r="10" fill="{INK}"/><circle cx="{side*22 + 3}" cy="-30" r="3.2" fill="{PALE}"/>'
c4 = f'''<g transform="translate(512 540) scale(3.5)">
  {glow(cy=0, rx=124, ry=134, op=0.6)}{contact(y=106, rx=76)}
  <ellipse cx="-78" cy="30" rx="13" ry="46" transform="rotate(9 -78 30)" fill="url(#darkLight)"/><ellipse cx="78" cy="30" rx="13" ry="46" transform="rotate(-9 78 30)" fill="url(#darkLight)"/>
  <path d="{PEN_BODY}" fill="{DARK_HI}"/>
  <g clip-path="url(#penBody)"><path d="{PEN_BODY}" fill="url(#darkLight)" transform="translate(3 4)"/></g>
  <path d="{PEN_BODY}" fill="url(#shadeBig)"/>
  <g clip-path="url(#penBody)"><ellipse cx="0" cy="66" rx="46" ry="42" fill="url(#creamLight)"/></g>
  <path d="{FACE}" fill="url(#creamLight)"/>
  {pen_eye(-1)}{pen_eye(1)}
  <path d="M-42,-50 L-8,-40 M42,-50 L8,-40" fill="none" stroke="{DARK}" stroke-width="8" stroke-linecap="round"/>
  <path d="M-11,-10 L11,-10 L0,8 Z" fill="{GOLD}" stroke="{GOLD}" stroke-width="3" stroke-linejoin="round"/>
  <path d="M-8,-1 L8,-1 L0,8 Z" fill="{GOLD_LO}"/>
  {band(30, 18, EMBER, "penBody")}
  <rect x="-44" y="42" width="22" height="46" rx="7" fill="{EMBER}"/><rect x="-44" y="80" width="22" height="8" rx="3" fill="{EMBER_LO}"/>
  <ellipse cx="-26" cy="100" rx="17" ry="8" fill="{GOLD}"/><ellipse cx="26" cy="100" rx="17" ry="8" fill="{GOLD}"/>
</g>'''

# ---------- 5 · Tiger (ember, ink stripes, fierce) ----------
_defs.append(f'<clipPath id="tigHead"><path d="{CAT_HEAD}"/></clipPath>')
tig_ear = f'<circle cx="-66" cy="-64" r="24" fill="url(#rimLight)"/><circle cx="-66" cy="-64" r="13" fill="{PINK}"/>'
TIG_MASK = "M-56,14 C-56,50 -30,84 0,84 C30,84 56,50 56,14 C40,30 -40,30 -56,14 Z"
stripes = (f'<g clip-path="url(#tigHead)" fill="{INK}">'
           f'<path d="M0,-78 C-8,-60 -6,-44 0,-30 C6,-44 8,-60 0,-78 Z"/>'
           f'<path d="M-30,-76 C-30,-62 -24,-52 -18,-44 C-20,-56 -22,-66 -30,-76 Z"/><path d="M30,-76 C30,-62 24,-52 18,-44 C20,-56 22,-66 30,-76 Z"/>'
           f'<path d="M-92,-10 C-78,-8 -68,0 -62,10 C-74,8 -84,2 -92,-10 Z"/><path d="M92,-10 C78,-8 68,0 62,10 C74,8 84,2 92,-10 Z"/>'
           f'<path d="M-90,22 C-78,22 -68,28 -62,38 C-74,36 -84,32 -90,22 Z"/><path d="M90,22 C78,22 68,28 62,38 C74,36 84,32 90,22 Z"/></g>')
tig_eye = lambda side: lidded(side * 36, 6, 15, 17, side,
    f'<ellipse cx="{side*36}" cy="6" rx="15" ry="17" fill="url(#coreLight)"/><circle cx="{side*36}" cy="8" r="8" fill="{INK}"/>'
    f'<circle cx="{side*36 + 4}" cy="1" r="3.4" fill="{PALE}"/>', slant=0.5, key="tig")
c5 = f'''<g transform="translate(512 548) scale(3.7)">
  {glow(cy=-6)}{contact(y=94, rx=84)}
  {tig_ear}{mirror(tig_ear)}
  <path d="{CAT_HEAD}" fill="url(#rimLight)"/><path d="{CAT_HEAD}" fill="url(#shadeBig)"/>
  <path d="{TIG_MASK}" fill="url(#creamLight)"/>
  {stripes}
  {specular(-40, -46, 16, 30, "tigHead")}
  {tig_eye(-1)}{tig_eye(1)}
  <path d="M-9,36 L9,36 L0,46 Z" fill="{PINK}" stroke="{PINK}" stroke-width="3" stroke-linejoin="round"/>
  <path d="M0,46 C-2,54 -10,56 -18,52 M0,46 C2,54 10,56 18,52" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>
</g>'''

CONCEPTS = {"11-hero-cat": c1, "12-focus-fox": c2, "13-owl": c3, "14-penguin": c4, "15-tiger": c5}

if __name__ == "__main__":
    SVG_DIR.mkdir(parents=True, exist_ok=True); OUT.mkdir(parents=True, exist_ok=True)
    extra = "<defs>" + "".join(_defs) + "</defs>"
    for name, body in CONCEPTS.items():
        p = SVG_DIR / f"{name}.svg"; p.write_text(svg(extra + body))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1024,1024",
                        f"--screenshot={OUT / (name + '.png')}", f"file://{p}"], capture_output=True)
        print("rendered", name)
