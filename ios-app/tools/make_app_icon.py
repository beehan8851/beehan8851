#!/usr/bin/env python3
"""
Writes the Dawnwick app icon sources from Embi's shape (D3, docs/18).

The drop path is copied verbatim from `Core/DesignSystem/EmbiView.swift`
(`EmbiShape.drop`, a 76 × 106 drop centred on the origin), so the icon, the app,
the widget and the Live Activity all share one silhouette.

Output (relative to the project root, next to the other design sources):

  design/ember-sky/icon/
    layers/            one 1024 × 1024 SVG per Icon Composer layer, drawn in place
    Dawnwick.icon/     an Icon Composer document already assembled from those layers
    composed/          light / dark / tinted as single SVGs (for PNG rendering, previews)
    README.md          how to open, adjust and add the icon to Xcode

PNGs for the asset catalogue are rendered by tools/render_app_icon.swift.

Run from the repo root:  python3 tools/make_app_icon.py
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PROJECT = REPO.parents[1]                # morning_companion_project
OUT = PROJECT / "design" / "ember-sky" / "icon"

# MARK: - Geometry (1024 canvas)

CANVAS = 1024
SCALE = 6.0                              # 106 × 6 = 636 pt tall, ~62 % of the canvas
CENTER = (512.0, 554.0)                  # the drop's bbox is -60…46, so +7 × 6 recentres it
CORE_SCALE = 0.62                        # EmbiShape.draw: core = drop × 0.62, 8 units lower
CORE_DY = 8.0
EYE_DX = 10.0                            # EmbiShape.draw: eyes at ±10, 8 lower, radius 5
EYE_DY = 8.0
EYE_SIZE = 5.0
EYE_OPENNESS = 1.0                       # idle — Embi awake, the canonical face

# The drop, from EmbiShape.drop.
DROP_PATH = (
    "M0,-60 "
    "C14,-36 38,-14 38,12 "
    "C38,32 22,46 0,46 "
    "C-22,46 -38,32 -38,12 "
    "C-38,-14 -14,-36 0,-60 Z"
)

# MARK: - Colours (tokens.json primitives; Embi's colours are fixed, not adaptive)

NIGHT_800 = "#14162B"                    # bg/ground dark — the icon plate (D1 context mock used it)
EMBER = "#F26B1D"
GOLD = "#F5B62B"
INK = "#1F1A17"
WHITE = "#FFFFFF"

# Tinted appearance: iOS reads luminance + alpha, so a grayscale drawing.
TINT_RIM = "#D2D2D2"
TINT_CORE = "#FAFAFA"
TINT_INK = "#262626"


def hex_to_extended_srgb(hex_colour: str) -> str:
    """Icon Composer writes fills as 'extended-srgb:r,g,b,a' in 0…1."""
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


# MARK: - SVG pieces

def svg(body: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">\n{body}\n</svg>\n'
    )


def rim(colour: str) -> str:
    cx, cy = CENTER
    return f'  <path transform="translate({cx:g} {cy:g}) scale({SCALE:g})" d="{DROP_PATH}" fill="{colour}"/>'


def core(colour: str) -> str:
    cx, cy = CENTER
    s = SCALE * CORE_SCALE
    return f'  <path transform="translate({cx:g} {cy + CORE_DY * SCALE:g}) scale({s:g})" d="{DROP_PATH}" fill="{colour}"/>'


def eyes(ink: str, highlight: str | None) -> str:
    cx, cy = CENTER
    y = cy + EYE_DY * SCALE
    size = EYE_SIZE * SCALE
    ry = size * 1.2 * EYE_OPENNESS
    parts = []
    for x in (cx - EYE_DX * SCALE, cx + EYE_DX * SCALE):
        parts.append(f'  <ellipse cx="{x:g}" cy="{y:g}" rx="{size:g}" ry="{ry:g}" fill="{ink}"/>')
        if highlight and EYE_OPENNESS > 0.5:
            # EmbiShape.draw: a highlight of 0.64 × size, offset (+0.1 size, -0.4 ry).
            d = size * 0.64
            hx = x + size * 0.1 + d / 2
            hy = y - ry * 0.4 + d / 2
            parts.append(f'  <circle cx="{hx:g}" cy="{hy:g}" r="{d / 2:g}" fill="{highlight}"/>')
    return "\n".join(parts)


def background(colour: str) -> str:
    return f'  <rect width="{CANVAS}" height="{CANVAS}" fill="{colour}"/>'


# MARK: - Files

def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print(f"  wrote {path.relative_to(PROJECT)}")


def write_layers() -> None:
    layers = OUT / "layers"
    write(layers / "background.svg", svg(background(NIGHT_800)))
    write(layers / "embi-rim.svg", svg(rim(EMBER)))
    write(layers / "embi-core.svg", svg(core(GOLD)))
    write(layers / "embi-eyes.svg", svg(eyes(INK, WHITE)))


def write_composed() -> None:
    composed = OUT / "composed"
    write(composed / "light.svg", svg("\n".join([background(NIGHT_800), rim(EMBER), core(GOLD), eyes(INK, WHITE)])))
    # Dark: no plate — iOS paints its own dark background behind a transparent icon.
    write(composed / "dark.svg", svg("\n".join([rim(EMBER), core(GOLD), eyes(INK, WHITE)])))
    # Tinted: grayscale on transparent — iOS tints by luminance.
    write(composed / "tinted.svg", svg("\n".join([rim(TINT_RIM), core(TINT_CORE), eyes(TINT_INK, None)])))


def write_icon_document() -> None:
    """An Icon Composer document (.icon bundle) with the layers already placed."""
    bundle = OUT / "Dawnwick.icon"
    assets = bundle / "Assets"
    if bundle.exists():
        shutil.rmtree(bundle)
    assets.mkdir(parents=True)
    for name in ("embi-eyes.svg", "embi-core.svg", "embi-rim.svg"):
        shutil.copy(OUT / "layers" / name, assets / name)

    def layer(name: str, glass: bool) -> dict:
        return {
            "fill": "automatic",
            "glass": glass,
            "hidden": False,
            "image-name": name,
            "name": Path(name).stem,
            "opacity": 1,
            "position": {"scale": 1, "translation-in-points": [0, 0]},
        }

    document = {
        # The plate. Icon Composer derives the dark and tinted plates from this itself;
        # the "Background" layer SVG is only for tools that cannot read this file.
        "fill": {"solid": hex_to_extended_srgb(NIGHT_800)},
        "groups": [
            {
                "name": "Embi",
                # Front-most first, as Icon Composer lists them.
                "layers": [
                    layer("embi-eyes.svg", glass=False),
                    layer("embi-core.svg", glass=True),
                    layer("embi-rim.svg", glass=True),
                ],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.5},
            }
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    write(bundle / "icon.json", json.dumps(document, indent=2) + "\n")


def write_readme() -> None:
    write(OUT / "README.md", f"""# Dawnwick app icon (D3)

Embi as the app icon: the drop of light from `EmbiShape` (D1 decision, 2026-09-09),
ember rim, gold core, eyes open, on a night plate ({NIGHT_800}). Everything here is
generated — do not edit by hand, run the tools again:

```bash
python3 tools/make_app_icon.py          # SVG layers, Dawnwick.icon, composed SVGs
swift tools/render_app_icon.swift       # PNGs into Assets.xcassets/AppIcon.appiconset + preview.png
```

(both from `ios-app/MorningCompanion/`).

## What is here

| Path | Purpose |
|---|---|
| `Dawnwick.icon/` | Icon Composer document, layers already placed. Open with Icon Composer (Xcode ▸ Open Developer Tool). |
| `layers/*.svg` | The individual layers at 1024 × 1024, drawn in place (scale 1, no offset). |
| `composed/*.svg` | Light / dark / tinted flattened, for previews and PNG rendering. |
| `preview.png` | The three appearances at home-screen size, for a glance. |

## Assembling in Icon Composer

1. Open `Dawnwick.icon`. Check the layer order: **eyes** in front, then **core**, then **rim**.
   If the rim hides the others, drag it to the bottom of the Embi group.
2. Judge the Liquid Glass: `rim` and `core` have glass on, `eyes` off. Turn glass off on
   `core` if the highlight fights the gold; the flat version is also fine.
3. Appearances tab: Dark keeps the same layers on the system's dark plate; Tinted and
   Clear are derived automatically. Nothing needs redrawing.
4. Save, then drag `Dawnwick.icon` into the Xcode project (target MorningCompanion) and
   set the target's **App Icon** to `Dawnwick`. Remove the PNGs from `AppIcon.appiconset`
   at that point, or leave both: Xcode 26 prefers the `.icon`.

## Until then

`render_app_icon.swift` fills `AppIcon.appiconset` with 1024 px PNGs (light opaque on the
night plate, dark on transparent, tinted grayscale on transparent), which is enough for
archive validation and for iOS 18-style icons. The `.icon` document is the better result
on iOS 26 — glass, clear and tinted variants come for free — so it is the one to ship.

## Geometry (for anyone touching the shape)

Canvas 1024. Drop at scale {SCALE:g}, centre ({CENTER[0]:g}, {CENTER[1]:g}) — the drop's box is
-60…46 tall, so the centre sits 42 pt low to centre the mass. Core = drop × {CORE_SCALE},
{CORE_DY:g} × {SCALE:g} pt lower. Eyes ±{EYE_DX:g} × {SCALE:g} pt, {EYE_DY:g} × {SCALE:g} pt low, radius {EYE_SIZE:g} × {SCALE:g},
openness {EYE_OPENNESS:g}. All of it mirrors `EmbiShape.draw`.
""")


def main() -> None:
    print(f"Writing icon sources to {OUT.relative_to(PROJECT)}")
    write_layers()
    write_composed()
    write_icon_document()
    write_readme()


if __name__ == "__main__":
    main()
