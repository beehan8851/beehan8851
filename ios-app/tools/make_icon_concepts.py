#!/usr/bin/env python3
"""Dawnwick app-icon concepts — hand-built SVG, lit with gradients/filters, rendered by headless Chrome."""
# Run from anywhere:  python3 tools/make_icon_concepts.py && python3 tools/make_icon_concepts_sheet.py
# Output: design/ember-sky/icon/concepts/{svg,png,sheet.png}. Needs Google Chrome (headless) and Pillow.
import subprocess, pathlib, textwrap
HERE = pathlib.Path(__file__).resolve().parents[3] / "design" / "ember-sky" / "icon" / "concepts"
SVG_DIR = HERE / "svg"; OUT = HERE / "png"; SVG_DIR.mkdir(parents=True, exist_ok=True); OUT.mkdir(parents=True, exist_ok=True)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

NIGHT, NIGHT_LO = "#1C1F3C", "#0F1126"
EMBER, EMBER_HI, EMBER_LO = "#F26B1D", "#FF9A4A", "#C4520F"
GOLD, GOLD_HI, GOLD_LO = "#F5B62B", "#FFE08A", "#E39A10"
INK, CREAM, PALE = "#1F1A17", "#FFF3D6", "#FFFFFF"
DROP = "M0,-60 C14,-36 38,-14 38,12 C38,32 22,46 0,46 C-22,46 -38,32 -38,12 C-38,-14 -14,-36 0,-60 Z"

DEFS = f"""
<defs>
  <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{NIGHT}"/><stop offset="1" stop-color="{NIGHT_LO}"/></linearGradient>
  <radialGradient id="rimLight" cx="0.36" cy="0.26" r="0.78">
    <stop offset="0" stop-color="{EMBER_HI}"/><stop offset="0.5" stop-color="{EMBER}"/><stop offset="1" stop-color="{EMBER_LO}"/></radialGradient>
  <radialGradient id="coreLight" cx="0.38" cy="0.28" r="0.8">
    <stop offset="0" stop-color="{GOLD_HI}"/><stop offset="0.55" stop-color="{GOLD}"/><stop offset="1" stop-color="{GOLD_LO}"/></radialGradient>
  <linearGradient id="bottomShade" gradientUnits="userSpaceOnUse" x1="0" y1="-60" x2="0" y2="46">
    <stop offset="0.55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.32"/></linearGradient>
  <filter id="bloom" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="14"/></filter>
  <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2"/></filter>
  <filter id="contact" x="-50%" y="-100%" width="200%" height="300%"><feGaussianBlur stdDeviation="3"/></filter>
  <clipPath id="dropClip"><path d="{DROP}"/></clipPath>
  <clipPath id="lidL"><polygon points="-18,0.5 -2.5,6.2 -2.5,24 -18,24"/></clipPath>
  <clipPath id="lidR"><polygon points="2.5,6.2 18,0.5 18,24 2.5,24"/></clipPath>
</defs>"""

def svg(body, plate="url(#plate)"):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{DEFS}\n<rect width="1024" height="1024" fill="{plate}"/>\n{body}\n</svg>\n'

def eyes(kind="determined", y=8, ry=7.0):
    """Embi's eyes in drop units. kind: determined (slanted lids) | wide (ringing)."""
    out = []
    for sx, clip in ((-1, "lidL"), (1, "lidR")):
        x = sx * 10
        cp = f' clip-path="url(#{clip})"' if kind == "determined" else ""
        rr = ry * (1.2 if kind == "wide" else 1.0)
        out.append(f'<g{cp}><ellipse cx="{x}" cy="{y}" rx="5.6" ry="{rr}" fill="{INK}"/>'
                   f'<circle cx="{x + 0.6}" cy="{y - rr * 0.35}" r="1.5" fill="{PALE}"/></g>')
    return "".join(out)

def embi_body(core=True, extra=""):
    """Lit drop + core (+ extra drawn inside the drop clip). Drop units."""
    s = f'<path d="{DROP}" fill="url(#rimLight)"/>'
    s += f'<path d="{DROP}" fill="url(#bottomShade)"/>'
    if core:
        s += f'<g transform="translate(0 8) scale(0.62)"><path d="{DROP}" fill="url(#coreLight)"/></g>'
    s += extra
    # specular, clipped to the drop
    s += (f'<g clip-path="url(#dropClip)"><ellipse cx="-13" cy="-24" rx="7" ry="15" '
          f'transform="rotate(22 -13 -24)" fill="{PALE}" opacity="0.22" filter="url(#soft)"/></g>')
    return s

def glow(rx=52, ry=62, op=0.42, cy=-2):
    return f'<ellipse cx="0" cy="{cy}" rx="{rx}" ry="{ry}" fill="{GOLD}" opacity="{op}" filter="url(#bloom)"/>'

def contact_shadow(y=50, rx=34, op=0.45):
    return f'<ellipse cx="0" cy="{y}" rx="{rx}" ry="6" fill="#000" opacity="{op}" filter="url(#contact)"/>'

# ---------- 1 · Embi awake (3D, determined) ----------
c1 = f'<g transform="translate(512 554) scale(6)">{glow()}{contact_shadow()}{embi_body()}{eyes("determined")}</g>'

# ---------- 2 · Embi ringing (the app's waking state) ----------
def ring_arcs(r1=60, r2=74, dx=8):
    out = ""
    for sx in (-1, 1):
        sweep = 0 if sx < 0 else 1
        out += (f'<path d="M{sx*r1},-22 A{r1},{r1} 0 0 {sweep} {sx*r1},22" fill="none" stroke="{GOLD}" stroke-width="3.8" stroke-linecap="round" opacity="0.95" transform="translate({sx*dx} -4)"/>'
                f'<path d="M{sx*r2},-30 A{r2},{r2} 0 0 {sweep} {sx*r2},30" fill="none" stroke="{GOLD}" stroke-width="3.2" stroke-linecap="round" opacity="0.45" transform="translate({sx*dx} -4)"/>')
    return out
sparks = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>' for x, y, r, c in
                 ((-44, -52, 2.6, GOLD), (46, -46, 2.2, EMBER), (-52, -14, 1.8, EMBER), (54, -8, 2.4, GOLD), (0, -78, 2.4, GOLD)))
c2 = f'''<g transform="translate(512 556) scale(5.7)">
  {glow(rx=60, ry=66, op=0.5, cy=-4)}
  {ring_arcs()}
  {sparks}
  {contact_shadow(y=52, rx=36)}
  <g transform="rotate(-7 0 46)">{embi_body()}{eyes("wide", y=8, ry=6.2)}</g>
</g>'''

# ---------- 3 · Embi mission (headband) ----------
band = (f'<g clip-path="url(#dropClip)"><rect x="-40" y="-27" width="80" height="12" fill="{CREAM}"/>'
        f'<rect x="-40" y="-17" width="80" height="2.2" fill="#000" opacity="0.18"/></g>'
        f'<circle cx="-2" cy="-21" r="3.6" fill="{EMBER}"/>')
tails = (f'<path d="M27,-24 C36,-30 44,-36 54,-38 C50,-33 47,-29 46,-24 C40,-24 34,-21 29,-18 Z" fill="{CREAM}"/>'
         f'<path d="M28,-18 C36,-17 44,-13 52,-6 C46,-7 41,-6 36,-3 C34,-9 31,-14 28,-16 Z" fill="{CREAM}"/>'
         f'<path d="M27,-24 C36,-30 44,-36 54,-38 C50,-33 47,-29 46,-24 C40,-24 34,-21 29,-18 Z" fill="#000" opacity="0.10"/>'
         f'<circle cx="27" cy="-21" r="4.8" fill="{CREAM}"/><circle cx="27" cy="-21" r="4.8" fill="#000" opacity="0.06"/>')
c3 = f'<g transform="translate(512 554) scale(6)">{glow()}{contact_shadow()}{embi_body()}{band}{tails}{eyes("determined")}</g>'

# ---------- 4 · No-Zzz (ember plate) ----------
Z = "M272,262 L752,262 L752,352 L412,672 L752,672 L752,762 L272,762 L272,672 L612,352 L272,352 Z"
c4 = f'''<defs>
  <radialGradient id="emberPlate" cx="0.3" cy="0.2" r="1.1"><stop offset="0" stop-color="#FF8A3A"/><stop offset="0.6" stop-color="{EMBER}"/><stop offset="1" stop-color="#D65A12"/></radialGradient>
  <filter id="zshadow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="16"/></filter>
</defs>
<rect width="1024" height="1024" fill="url(#emberPlate)"/>
<path d="{Z}" fill="#000" opacity="0.28" filter="url(#zshadow)" transform="translate(0 22)"/>
<path d="{Z}" fill="{CREAM}"/>
<path d="{Z}" fill="url(#bottomShade)" transform="translate(512 512) scale(4.8) translate(-106.6 -106.6)" opacity="0"/>
<line x1="262" y1="262" x2="762" y2="762" stroke="#000" stroke-width="100" stroke-linecap="round" opacity="0.25" filter="url(#zshadow)" transform="translate(0 18)"/>
<line x1="262" y1="262" x2="762" y2="762" stroke="{INK}" stroke-width="100" stroke-linecap="round"/>
<line x1="270" y1="256" x2="768" y2="754" stroke="{PALE}" stroke-width="10" stroke-linecap="round" opacity="0.12"/>'''

# ---------- 5 · Dawnbreak (Embi rises) ----------
H = 790
rays = "".join(
    f'<polygon points="512,{H} {512 + 1400 * __import__("math").cos(__import__("math").radians(a - 3)):.0f},{H + 1400 * __import__("math").sin(__import__("math").radians(a - 3)):.0f} '
    f'{512 + 1400 * __import__("math").cos(__import__("math").radians(a + 3)):.0f},{H + 1400 * __import__("math").sin(__import__("math").radians(a + 3)):.0f}" fill="{GOLD}" opacity="{0.07 if i % 2 else 0.12}"/>'
    for i, a in enumerate(range(-160, -19, 20)))
c5 = f'''<defs>
  <linearGradient id="dawnSky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E1026"/><stop offset="0.62" stop-color="#232042"/><stop offset="1" stop-color="#4A2E3E"/></linearGradient>
  <clipPath id="skyClip"><rect x="0" y="0" width="1024" height="{H}"/></clipPath>
</defs>
<rect width="1024" height="1024" fill="url(#dawnSky)"/>
<g clip-path="url(#skyClip)">
  {rays}
  <ellipse cx="512" cy="{H}" rx="330" ry="240" fill="{GOLD}" opacity="0.5" filter="url(#bloom)"/>
  <g transform="translate(512 688) scale(5.2)">{embi_body()}{eyes("determined")}</g>
</g>
<rect x="0" y="{H}" width="1024" height="{1024 - H}" fill="#0B0B1A"/>
<rect x="0" y="{H - 3}" width="1024" height="6" fill="{GOLD}" opacity="0.85"/>
<rect x="0" y="{H - 14}" width="1024" height="28" fill="{GOLD}" opacity="0.25" filter="url(#soft)"/>'''

# ---------- 6 · Rooster (Xo'roz) ----------
c6 = f'''<defs>
  <radialGradient id="headLight" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="{EMBER_HI}"/><stop offset="0.5" stop-color="{EMBER}"/><stop offset="1" stop-color="{EMBER_LO}"/></radialGradient>
  <linearGradient id="neckShade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{EMBER}"/><stop offset="1" stop-color="#7E330A"/></linearGradient>
  <radialGradient id="combLight" cx="0.4" cy="0.3" r="0.8"><stop offset="0" stop-color="#E5583A"/><stop offset="1" stop-color="#A2330F"/></radialGradient>
</defs>
<ellipse cx="500" cy="500" rx="240" ry="260" fill="{GOLD}" opacity="0.28" filter="url(#bloom)"/>
<!-- crow: three wedges -->
<g fill="{GOLD}">
  <polygon points="822,380 900,330 908,352 836,396"/><polygon points="846,462 936,452 936,476 846,482"/><polygon points="822,548 900,596 890,616 816,566"/>
</g>
<!-- neck (S curve) -->
<path d="M400,570 C400,690 372,820 340,1040 L640,1040 C628,860 610,720 580,600 Z" fill="url(#neckShade)"/>
<!-- hackle shadow under the head -->
<path d="M400,570 C440,640 540,650 580,600 L590,640 C540,700 430,690 396,620 Z" fill="#000" opacity="0.22" filter="url(#soft)"/>
<!-- wattle -->
<path d="M560,606 C600,606 640,640 632,700 C620,740 560,740 552,690 Z" fill="url(#combLight)"/>
<!-- comb: five lobes -->
<g fill="url(#combLight)">
  <circle cx="378" cy="372" r="46"/><circle cx="436" cy="300" r="54"/><circle cx="508" cy="262" r="60"/><circle cx="582" cy="290" r="54"/><circle cx="640" cy="352" r="44"/>
  <path d="M378,372 L640,352 L640,470 L378,470 Z"/>
</g>
<!-- head -->
<circle cx="500" cy="480" r="150" fill="url(#headLight)"/>
<!-- open beak -->
<polygon points="630,436 806,458 636,492" fill="url(#coreLight)"/>
<polygon points="628,500 782,584 618,556" fill="{GOLD_LO}"/>
<polygon points="636,494 700,504 634,522" fill="{INK}" opacity="0.55"/>
<!-- eye -->
<circle cx="556" cy="446" r="32" fill="{CREAM}"/>
<circle cx="566" cy="452" r="16" fill="{INK}"/>
<circle cx="572" cy="446" r="4.5" fill="{PALE}"/>
<path d="M516,400 L600,412 L600,440 L516,436 Z" fill="url(#headLight)"/>
<path d="M514,404 L602,418 L602,430 L514,420 Z" fill="{INK}"/>
<!-- specular -->
<ellipse cx="436" cy="400" rx="30" ry="56" transform="rotate(25 436 400)" fill="{PALE}" opacity="0.18" filter="url(#soft)"/>'''

CONCEPTS = {
    "01-embi-awake": svg(c1),
    "02-embi-ringing": svg(c2),
    "03-embi-mission": svg(c3),
    "04-no-zzz": svg(c4, plate="none"),
    "05-dawnbreak": svg(c5, plate="none"),
    "06-rooster": svg(c6),
}

if __name__ == "__main__":
    for name, s in CONCEPTS.items():
        p = SVG_DIR / f"{name}.svg"; p.write_text(s)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1024,1024",
                        f"--screenshot={OUT / (name + '.png')}", f"file://{p}"], capture_output=True)
        print("rendered", name)
