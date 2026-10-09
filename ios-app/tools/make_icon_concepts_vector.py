#!/usr/bin/env python3
"""Packages the vector icon concepts for Figma.

Output (design/ember-sky/icon/concepts-vector/):
  svg/NN-name.svg    one icon each, clipped to the iOS squircle, layers named
  all-icons.svg      all eight in a 4x2 grid — one drag/paste gives the whole set
  png/NN-name.png    1024 px previews
Dropping (or pasting) any of these into Figma produces native vector layers,
not an image: every `id` becomes a Figma layer name.
"""
import re, subprocess, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from icon_concepts_vector_art import ICONS  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[0]
OUT = pathlib.Path(__file__).resolve().parents[3] / "design" / "ember-sky" / "icon" / "concepts-vector"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

TITLES = {
    "01-hero-cat":        "01 Hero Cat",
    "02-sunrise-mission": "02 Sunrise and Mission",
    "03-mission-bell":    "03 Mission Bell",
    "04-dreamer-penguin": "04 Dreamer Penguin",
    "05-moon-cat":        "05 Moon and Cat",
    "06-peak-goal":       "06 Peak and Goal",
    "07-focus-fox":       "07 Focus Fox",
    "08-abstract-star":   "08 Abstract Star",
}
R = 230  # iOS squircle radius at 1024

def minify(s):
    return re.sub(r"\s{2,}", " ", re.sub(r">\s+<", "><", s)).strip()

def split(svg):
    """Returns (defs_inner, body) for a document produced by icons.py."""
    d0 = svg.index("<defs>") + len("<defs>")
    d1 = svg.index("</defs>")
    return svg[d0:d1], svg[d1 + len("</defs>"):svg.rindex("</svg>")]

def single(key, svg):
    defs, body = split(svg)
    cid = f"clip-{key}"
    return minify(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f'<defs>{defs}<clipPath id="{cid}"><rect width="1024" height="1024" rx="{R}" ry="{R}"/></clipPath></defs>'
        f'<g id="{TITLES[key]}" clip-path="url(#{cid})">{body}</g></svg>')

def combined(items, cols=4, gap=200):
    cell = 1024 + gap
    w = cols * cell - gap
    rows = (len(items) + cols - 1) // cols
    h = rows * cell - gap
    defs, groups = [], []
    for i, (key, svg) in enumerate(items):
        d, body = split(svg)
        cid = f"clip-{key}"
        defs.append(d)
        defs.append(f'<clipPath id="{cid}"><rect width="1024" height="1024" rx="{R}" ry="{R}"/></clipPath>')
        x, y = (i % cols) * cell, (i // cols) * cell
        groups.append(f'<g id="{TITLES[key]}" transform="translate({x} {y})">'
                      f'<g clip-path="url(#{cid})">{body}</g></g>')
    return minify(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                  f'<defs>{"".join(defs)}</defs><g id="Icon Concepts">{"".join(groups)}</g></svg>')

if __name__ == "__main__":
    (OUT / "svg").mkdir(parents=True, exist_ok=True)
    (OUT / "png").mkdir(parents=True, exist_ok=True)
    items = sorted(ICONS.items())
    for key, svg in items:
        p = OUT / "svg" / f"{key}.svg"
        p.write_text(single(key, svg))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000", "--window-size=1024,1024",
                        f"--screenshot={OUT / 'png' / (key + '.png')}", f"file://{p}"], capture_output=True)
    allp = OUT / "all-icons.svg"
    allp.write_text(combined(items))
    print("wrote", len(items), "svg +", allp.name, allp.stat().st_size, "bytes")
