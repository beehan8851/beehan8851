#!/usr/bin/env python3
"""Vector rebuilds of the 8 'Mission' app-icon concepts, authored as Figma-importable SVG.
Figma's SVG import keeps gradients, opacity, strokes and clip paths, and names layers from `id`.
No <filter> is used — soft light is done with multi-stop radial gradients."""
import math, subprocess, pathlib
HERE = pathlib.Path(__file__).parent
SVG, PNG = HERE / "svg", HERE / "png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

def rg(id_, cx, cy, r, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{id_}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'

def lg(id_, x1, y1, x2, y2, stops):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{id_}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>'

def star4(cx, cy, r, inner=0.30, fill="#FFD36B", id_="star"):
    i = r * inner
    d = (f"M{cx},{cy-r} C{cx+i*0.5},{cy-i*1.1} {cx+i*1.1},{cy-i*0.5} {cx+r},{cy} "
         f"C{cx+i*1.1},{cy+i*0.5} {cx+i*0.5},{cy+i*1.1} {cx},{cy+r} "
         f"C{cx-i*0.5},{cy+i*1.1} {cx-i*1.1},{cy+i*0.5} {cx-r},{cy} "
         f"C{cx-i*1.1},{cy-i*0.5} {cx-i*0.5},{cy-i*1.1} {cx},{cy-r} Z")
    return f'<path id="{id_}" d="{d}" fill="{fill}"/>'

def doc(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>')


def crescent(c1, r1, c2, r2):
    """Exact crescent: the part of circle 1 outside circle 2, as two arcs (no fill-rule tricks)."""
    (x1, y1), (x2, y2) = c1, c2
    dx, dy = x2 - x1, y2 - y1
    d = math.hypot(dx, dy)
    a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    h = math.sqrt(max(r1 * r1 - a * a, 0.0))
    px, py = x1 + a * dx / d, y1 + a * dy / d
    ox, oy = -h * dy / d, h * dx / d
    P1 = (px + ox, py + oy)
    P2 = (px - ox, py - oy)

    def ang(p, c):
        return math.degrees(math.atan2(p[1] - c[1], p[0] - c[0]))

    def sweep_for(start, end, through, c, r):
        """Pick (large-arc, sweep) for the arc from start to end that passes through `through`."""
        best = None
        for large in (0, 1):
            for sw in (0, 1):
                a0, a1 = math.radians(ang(start, c)), math.radians(ang(end, c))
                delta = a1 - a0
                if sw == 1:
                    while delta <= 0: delta += 2 * math.pi
                else:
                    while delta >= 0: delta -= 2 * math.pi
                if (abs(delta) > math.pi) != bool(large):
                    continue
                mid = a0 + delta / 2
                mp = (c[0] + r * math.cos(mid), c[1] + r * math.sin(mid))
                dist = math.hypot(mp[0] - through[0], mp[1] - through[1])
                if best is None or dist < best[0]:
                    best = (dist, large, sw)
        return best[1], best[2]

    far = (x1 - (x2 - x1) / d * r1, y1 - (y2 - y1) / d * r1)          # outer edge, away from circle 2
    inner_through = (x2 - (x2 - x1) / d * r2, y2 - (y2 - y1) / d * r2)  # circle 2's edge, inside circle 1
    l1, s1 = sweep_for(P2, P1, far, c1, r1)
    l2, s2 = sweep_for(P1, P2, inner_through, c2, r2)
    return (f"M{P2[0]:.1f},{P2[1]:.1f} A{r1},{r1} 0 {l1} {s1} {P1[0]:.1f},{P1[1]:.1f} "
            f"A{r2},{r2} 0 {l2} {s2} {P2[0]:.1f},{P2[1]:.1f} Z")

ICONS = {}

# ─────────────────────────────── 1 · Hero Cat ───────────────────────────────
defs = "".join([
    lg("hcSky", 0, 0, 0, 1024, [(0, "#191A44", 1), (0.5, "#2B1F4D", 1), (1, "#4C2C50", 1)]),
    rg("hcSun", 430, 420, 320, [(0, "#FFEDBC", 1), (0.5, "#FBC964", 1), (1, "#F2A03C", 1)]),
    rg("hcHalo", 430, 420, 500, [(0, "#FFC46A", 0.5), (0.45, "#FF9E45", 0.24), (1, "#FF8A3C", 0)]),
    lg("hcFur", 250, 240, 640, 800, [(0, "#FFFAF0", 1), (0.45, "#FBE6C8", 1), (1, "#EEC79D", 1)]),
    lg("hcFurLit", 300, 260, 560, 620, [(0, "#FFFDF6", 1), (1, "#F7DDB9", 1)]),
    lg("hcBand", 220, 300, 660, 400, [(0, "#FFB662", 1), (0.45, "#F6912F", 1), (1, "#DE6D1B", 1)]),
    lg("hcCloudA", 0, 720, 0, 1024, [(0, "#FFFFFF", 1), (0.5, "#F4EDF8", 1), (1, "#DED2EA", 1)]),
    lg("hcCloudB", 0, 830, 0, 1024, [(0, "#EFE6F5", 1), (1, "#C9B9DE", 1)]),
])
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#hcSky)"/>
<ellipse id="halo" cx="430" cy="420" rx="500" ry="500" fill="url(#hcHalo)"/>
<circle id="sun" cx="430" cy="420" r="318" fill="url(#hcSun)"/>
{star4(806, 214, 54, 0.32, "#FFD36B", "sparkle")}
<g id="cat">
  <path id="chest" d="M250,860 C250,752 330,690 442,690 C554,690 634,752 634,860 L634,1000 L250,1000 Z" fill="url(#hcFur)"/>
  <g id="arm">
    <path id="arm-shadow" d="M624,684 C612,580 632,486 686,430 C752,378 822,376 860,424 C900,476 894,558 844,612 C796,664 706,704 652,708 Z" fill="#C99A6B" opacity="0.45"/>
    <path id="arm-limb" d="M636,672 C624,572 644,482 696,428 C760,378 826,376 862,424 C900,474 894,554 846,606 C798,656 714,694 662,698 Z" fill="url(#hcFur)"/>
    <g id="paw">
      <path d="M706,438 C706,378 752,342 806,350 C862,358 892,410 880,464 C870,510 828,536 778,528 C732,520 706,484 706,438 Z" fill="url(#hcFurLit)"/>
      <g id="toes" fill="#F0CCA3"><ellipse cx="746" cy="410" rx="27" ry="31" transform="rotate(-14 746 410)"/>
        <ellipse cx="804" cy="390" rx="27" ry="31" transform="rotate(-4 804 390)"/>
        <ellipse cx="856" cy="416" rx="25" ry="29" transform="rotate(10 856 416)"/></g>
    </g>
  </g>
  <g id="ears">
    <path id="ear-left" d="M226,392 C204,296 226,236 278,232 C326,228 374,270 398,338 Z" fill="url(#hcFur)"/>
    <path id="ear-left-inner" d="M258,368 C246,300 258,266 288,266 C316,266 346,298 360,340 Z" fill="#F3A78B"/>
    <path id="ear-right" d="M578,318 C616,254 668,224 708,240 C752,258 758,320 736,398 Z" fill="url(#hcFur)"/>
    <path id="ear-right-inner" d="M612,320 C638,280 670,262 692,272 C716,284 716,322 702,368 Z" fill="#F3A78B"/>
  </g>
  <path id="head" d="M198,520 C198,364 306,282 442,282 C582,282 686,366 686,524 C686,684 582,780 442,780 C304,780 198,682 198,520 Z" fill="url(#hcFur)"/>
  <path id="head-lit" d="M236,472 C272,378 348,330 430,330 C348,352 286,404 252,486 Z" fill="#FFFDF4" opacity="0.4"/>
  <g id="headband">
    <path id="band" d="M206,470 C286,412 364,388 442,388 C522,388 604,414 660,462 C664,492 664,512 660,532 C598,478 522,452 442,452 C362,452 272,482 210,534 C202,512 202,490 206,470 Z" fill="url(#hcBand)"/>
    <path id="band-lit" d="M218,474 C292,424 368,402 442,402 C514,402 590,424 644,464 C592,436 518,424 442,424 C366,424 284,444 218,474 Z" fill="#FFC078" opacity="0.35"/>
    {star4(436, 432, 30, 0.36, "#FFE9AE", "band-star")}
    <g id="band-knot">
      <path d="M186,522 C156,556 132,598 120,642 C154,634 186,612 208,578 Z" fill="#E2731E"/>
      <path d="M206,542 C196,586 194,628 202,668 C222,634 232,592 226,552 Z" fill="#EB7C22"/>
      <ellipse cx="204" cy="514" rx="36" ry="32" fill="#F28A29"/>
    </g>
  </g>
  <g id="face">
    <path id="eye-left" d="M302,560 C322,594 362,596 386,566" fill="none" stroke="#4B3523" stroke-width="19" stroke-linecap="round"/>
    <path id="eye-right" d="M506,562 C526,596 566,596 590,566" fill="none" stroke="#4B3523" stroke-width="19" stroke-linecap="round"/>
    <ellipse id="blush-left" cx="284" cy="630" rx="38" ry="22" fill="#F2A184" opacity="0.6"/>
    <ellipse id="blush-right" cx="606" cy="630" rx="38" ry="22" fill="#F2A184" opacity="0.6"/>
    <path id="nose" d="M418,618 L466,618 C468,638 448,652 442,652 C436,652 416,638 418,618 Z" fill="#E8916F"/>
    <path id="mouth" d="M442,656 C442,682 416,690 400,676 M442,656 C442,682 468,690 484,676" fill="none" stroke="#D9885F" stroke-width="10" stroke-linecap="round"/>
    
  </g>
</g>
<g id="clouds">
  <path id="cloud-back" d="M-40,880 C30,802 140,798 198,850 C242,788 344,782 392,840 C450,794 546,802 580,862 C644,816 748,828 782,886 C844,854 940,868 1064,924 L1064,1064 L-40,1064 Z" fill="url(#hcCloudA)"/>
  <path id="cloud-front" d="M-40,982 C36,928 146,930 198,972 C266,926 368,930 412,980 C476,940 574,950 610,996 L1064,1030 L1064,1064 L-40,1064 Z" fill="url(#hcCloudB)"/>
</g>'''
ICONS["01-hero-cat"] = doc(defs, body)

# ─────────────────────────────── 2 · Sunrise & Mission ───────────────────────────────
defs = "".join([
    lg("srSky", 0, 0, 0, 1024, [(0, "#101840", 1), (0.5, "#241A46", 1), (1, "#4A2247", 1)]),
    rg("srSun", 512, 590, 260, [(0, "#FFF6CE", 1), (0.45, "#FDD873", 1), (1, "#F6A93F", 1)]),
    rg("srHalo", 512, 590, 470, [(0, "#FFC061", 0.45), (0.5, "#FF9A42", 0.2), (1, "#FF8A3C", 0)]),
    lg("srHillA", 0, 720, 0, 1000, [(0, "#F9A349", 1), (1, "#E2762C", 1)]),
    lg("srHillB", 0, 760, 0, 1010, [(0, "#E07A35", 1), (1, "#BE5726", 1)]),
    lg("srHillC", 0, 800, 0, 1020, [(0, "#A9502F", 1), (1, "#7C3728", 1)]),
])
rays = "".join(
    f'<rect id="ray-{i}" x="-18" y="-56" width="36" height="112" rx="18" fill="#FBA23F" '
    f'transform="translate({512 + 356 * math.cos(math.radians(a)):.0f} {590 + 356 * math.sin(math.radians(a)):.0f}) rotate({a + 90})"/>'
    for i, a in enumerate((-162, -132, -48, -18)))
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#srSky)"/>
<ellipse id="halo" cx="512" cy="590" rx="470" ry="470" fill="url(#srHalo)"/>
<g id="rays">{rays}</g>
{star4(512, 182, 60, 0.32, "#FFD36B", "sparkle")}
<circle id="sun" cx="512" cy="590" r="222" fill="url(#srSun)"/>
<g id="hills">
  <path id="hill-back" d="M-30,1064 C-10,912 96,806 216,812 C330,818 404,916 436,1064 Z" fill="url(#srHillC)"/>
  <path id="hill-right" d="M596,1064 C636,918 728,830 830,838 C930,846 1004,936 1054,1064 Z" fill="url(#srHillC)"/>
  <path id="hill-mid" d="M180,1064 C232,880 356,772 500,782 C636,792 726,896 776,1064 Z" fill="url(#srHillB)"/>
  <path id="hill-front" d="M-40,1064 C40,930 180,846 330,858 C474,870 560,962 600,1064 Z" fill="url(#srHillA)"/>
  <path id="hill-front-2" d="M480,1064 C540,952 650,890 766,900 C880,910 964,982 1010,1064 Z" fill="url(#srHillA)"/>
</g>'''
ICONS["02-sunrise-mission"] = doc(defs, body)

# ─────────────────────────────── 3 · Mission Bell ───────────────────────────────
defs = "".join([
    rg("mbBg", 512, 440, 640, [(0, "#FFF8EC", 1), (0.6, "#FCE8CE", 1), (1, "#F5DCBC", 1)]),
    lg("mbBell", 300, 220, 720, 760, [(0, "#FFC978", 1), (0.3, "#FB9B3C", 1), (1, "#EA6A1F", 1)]),
    lg("mbGloss", 330, 250, 460, 600, [(0, "#FFFFFF", 0.8), (1, "#FFFFFF", 0)]),
    lg("mbRingA", 120, 470, 904, 700, [(0, "#FFC069", 1), (0.3, "#F98B33", 1), (0.55, "#F4772B", 1), (0.78, "#9E5CD8", 1), (1, "#4E7BF0", 1)]),
    lg("mbBase", 400, 780, 640, 880, [(0, "#FA9D3E", 1), (1, "#DF661E", 1)]),
    rg("mbStar", 476, 500, 130, [(0, "#FFEFB8", 1), (1, "#F6B23D", 1)]),
])
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#mbBg)"/>
<g id="ticks" fill="#FBA23F">
  <rect x="-16" y="-44" width="32" height="88" rx="16" transform="translate(206 318) rotate(-40)"/>
  <rect x="-16" y="-44" width="32" height="88" rx="16" transform="translate(818 306) rotate(38)"/>
  <rect x="-14" y="-38" width="28" height="76" rx="14" transform="translate(154 500) rotate(-88)" opacity="0.55"/>
  <rect x="-14" y="-38" width="28" height="76" rx="14" transform="translate(872 492) rotate(86)" opacity="0.55"/>
</g>
<ellipse id="orbit-back" cx="512" cy="586" rx="392" ry="152" fill="none" stroke="url(#mbRingA)" stroke-width="30" transform="rotate(-9 512 586)"/>
<g id="bell">
  <path id="bell-handle" d="M512,118 C556,118 586,150 586,194 C586,228 566,254 536,264 L500,232 C476,222 462,200 462,174 C462,140 482,118 512,118 Z M512,158 C494,158 484,172 486,190 C488,208 502,218 518,214 C536,210 544,192 538,176 C532,162 524,158 512,158 Z" fill="url(#mbBell)"/>
  <path id="bell-body" d="M512,214 C664,214 748,392 762,600 C768,680 748,726 700,742 L324,742 C276,726 256,680 262,600 C276,392 360,214 512,214 Z" fill="url(#mbBell)"/>
  <path id="bell-gloss" d="M452,278 C390,352 352,468 342,606 C338,676 350,712 380,724 C350,700 342,656 346,584 C356,448 396,336 462,272 Z" fill="url(#mbGloss)"/>
  <ellipse id="bell-rim" cx="512" cy="742" rx="252" ry="42" fill="#F5902F"/>
  <ellipse id="bell-rim-lit" cx="512" cy="734" rx="252" ry="36" fill="#FFC271" opacity="0.6"/>
  <path id="clapper-stem" d="M474,774 C474,756 550,756 550,774 C550,804 536,824 512,824 C488,824 474,804 474,774 Z" fill="url(#mbBase)"/>
  <circle id="clapper" cx="512" cy="854" r="46" fill="url(#mbBase)"/>
  {star4(486, 512, 116, 0.42, "url(#mbStar)", "bell-star")}
</g>
<g id="orbit-front" transform="rotate(-9 512 586)"><path d="M120,586 A392,152 0 0 1 904,586" fill="none" stroke="url(#mbRingA)" stroke-width="30" stroke-linecap="round"/><path d="M196,676 C170,652 162,626 174,604" fill="none" stroke="#FFFFFF" stroke-width="11" stroke-linecap="round" opacity="0.55"/></g>'''
ICONS["03-mission-bell"] = doc(defs, body)

# ─────────────────────────────── 4 · Dreamer Penguin ───────────────────────────────
defs = "".join([
    lg("dpSky", 0, 0, 0, 1024, [(0, "#2A36A6", 1), (0.4, "#17235F", 1), (1, "#070B24", 1)]),
    rg("dpGlow", 812, 520, 440, [(0, "#FFD888", 0.9), (0.38, "#FBA24A", 0.45), (1, "#F08A3C", 0)]),
    rg("dpSun", 812, 502, 170, [(0, "#FFF3C8", 1), (0.55, "#FCC85F", 1), (1, "#F5A03A", 1)]),
    lg("dpBody", 220, 240, 700, 940, [(0, "#333A5E", 1), (0.4, "#191E3B", 1), (1, "#080B1D", 1)]),
    lg("dpBelly", 330, 420, 600, 880, [(0, "#FFFFFF", 1), (0.5, "#FCF3E6", 1), (1, "#E9D7C4", 1)]),
    lg("dpBeak", 560, 470, 720, 560, [(0, "#FDBE63", 1), (1, "#EE7C25", 1)]),
    rg("dpOrb", 846, 828, 112, [(0, "#FFF0BC", 1), (0.55, "#FBC262", 1), (1, "#F19B3C", 1)]),
])
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#dpSky)"/>
<g id="stars" fill="#FFFFFF">
  <circle cx="172" cy="188" r="4" opacity="0.8"/><circle cx="286" cy="122" r="3" opacity="0.6"/>
  <circle cx="142" cy="322" r="3.5" opacity="0.5"/><circle cx="360" cy="196" r="2.5" opacity="0.5"/>
  <circle cx="880" cy="196" r="3.5" opacity="0.6"/><circle cx="936" cy="320" r="2.5" opacity="0.45"/></g>
{star4(600, 196, 54, 0.32, "#FFD96F", "sparkle")}
<ellipse id="glow" cx="812" cy="520" rx="440" ry="440" fill="url(#dpGlow)"/>
<circle id="sun" cx="812" cy="502" r="152" fill="url(#dpSun)"/>
<g id="penguin">
  <path id="wing-left" d="M212,656 C140,742 116,878 152,1032 L300,1032 C238,918 216,780 244,648 Z" fill="url(#dpBody)"/>
  <path id="wing-right" d="M770,706 C844,800 872,942 838,1032 L688,1032 C752,946 778,818 770,708 Z" fill="url(#dpBody)"/>
  <path id="silhouette" d="M480,214 C664,214 786,364 786,586 C786,700 806,840 806,932 C806,1004 762,1040 660,1040 L300,1040 C204,1040 166,1000 166,932 C166,838 186,700 186,586 C186,364 302,214 480,214 Z" fill="url(#dpBody)"/>
  <path id="head-gloss" d="M254,438 C300,326 388,266 484,262 C398,288 320,354 280,472 Z" fill="#FFFFFF" opacity="0.13"/>
  <path id="face" d="M474,314 C596,314 656,398 656,502 C656,606 586,668 474,668 C378,668 322,600 322,500 C322,396 380,314 474,314 Z" fill="url(#dpBelly)"/>
  <path id="belly" d="M478,726 C602,726 668,806 668,902 C668,984 636,1040 478,1040 C322,1040 290,984 290,902 C290,806 354,726 478,726 Z" fill="url(#dpBelly)"/>
  <path id="eye-left" d="M400,480 C418,440 464,436 486,472" fill="none" stroke="#1C1C30" stroke-width="22" stroke-linecap="round"/>
  <path id="eye-right" d="M548,472 C568,436 610,440 626,478" fill="none" stroke="#1C1C30" stroke-width="22" stroke-linecap="round"/>
  <ellipse id="blush-left" cx="378" cy="560" rx="40" ry="24" fill="#F09898" opacity="0.55"/>
  <ellipse id="blush-right" cx="604" cy="562" rx="34" ry="21" fill="#F09898" opacity="0.4"/>
  <path id="beak" d="M572,520 C632,494 700,506 730,546 C690,588 620,596 578,574 C558,560 558,532 572,520 Z" fill="url(#dpBeak)"/>
  <path id="beak-line" d="M586,558 C634,570 688,562 722,548" fill="none" stroke="#D4681B" stroke-width="9" stroke-linecap="round" opacity="0.6"/>
</g>
<circle id="orb" cx="866" cy="842" r="86" fill="url(#dpOrb)" opacity="0.92"/>'''
ICONS["04-dreamer-penguin"] = doc(defs, body)


# ─────────────────────────────── 5 · Moon & Cat ───────────────────────────────
defs = "".join([
    lg("mcSky", 0, 0, 0, 1024, [(0, "#1D1740", 1), (0.55, "#2A2050", 1), (1, "#3A2A58", 1)]),
    rg("mcMoonGlow", 226, 404, 400, [(0, "#FFD584", 0.5), (0.45, "#FBA94D", 0.2), (1, "#F59A3C", 0)]),
    lg("mcMoon", 120, 130, 560, 660, [(0, "#FFF3C8", 1), (0.45, "#FCD374", 1), (1, "#F2A23C", 1)]),
    lg("mcFur", 400, 580, 720, 940, [(0, "#FFF8EA", 1), (0.5, "#FBE3C0", 1), (1, "#EFC998", 1)]),
    lg("mcCap", 400, 620, 720, 700, [(0, "#FFB25E", 1), (0.5, "#F68E2C", 1), (1, "#E1701C", 1)]),
    lg("mcCloudA", 0, 700, 0, 1024, [(0, "#EFE9FC", 1), (0.5, "#DAD3F5", 1), (1, "#BAB3E7", 1)]),
    lg("mcCloudB", 0, 830, 0, 1024, [(0, "#DED7F7", 1), (1, "#ABA4DD", 1)]),
    lg("mcCloudC", 0, 910, 0, 1024, [(0, "#C9C1ED", 1), (1, "#9B94CF", 1)]),
])
CRESCENT = crescent((350, 404), 272, (472, 328), 286)
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#mcSky)"/>
<ellipse id="moon-glow" cx="226" cy="404" rx="400" ry="400" fill="url(#mcMoonGlow)"/>
<path id="moon" d="{CRESCENT}" fill="url(#mcMoon)"/>
{star4(694, 300, 60, 0.34, "#FFD97A", "sparkle")}
<path id="cloud-back" d="M-40,748 C42,662 158,658 220,718 C272,646 386,640 440,706 C504,654 608,664 646,730 C716,678 830,692 868,758 L1064,800 L1064,1064 L-40,1064 Z" fill="url(#mcCloudA)"/>
<g id="cat" transform="translate(58 -16) scale(0.9)">
  <path id="ear-left" d="M378,634 C360,566 386,522 440,522 C486,522 530,556 552,600 Z" fill="url(#mcFur)"/>
  <path id="ear-left-inner" d="M406,620 C398,574 412,548 442,548 C470,548 496,572 510,600 Z" fill="#F0A188"/>
  <path id="ear-right" d="M648,600 C670,548 712,516 754,528 C796,542 798,592 780,650 Z" fill="url(#mcFur)"/>
  <path id="ear-right-inner" d="M674,600 C692,568 720,552 744,562 C766,574 766,602 756,634 Z" fill="#F0A188"/>
  <ellipse id="head" cx="580" cy="764" rx="222" ry="196" fill="url(#mcFur)"/>
  <path id="cap" d="M366,696 C432,630 500,600 580,600 C660,600 730,632 788,690 C792,718 792,736 788,754 C724,704 656,678 580,678 C500,678 424,708 372,756 C364,736 362,716 366,696 Z" fill="url(#mcCap)"/>
  {star4(576, 640, 28, 0.36, "#FFE7A8", "cap-star")}
  <path id="eye-left" d="M462,788 C480,818 518,820 540,792" fill="none" stroke="#4B3523" stroke-width="17" stroke-linecap="round"/>
  <path id="eye-right" d="M622,790 C640,820 678,820 700,792" fill="none" stroke="#4B3523" stroke-width="17" stroke-linecap="round"/>
  <ellipse id="blush-left" cx="442" cy="844" rx="34" ry="20" fill="#F2A184" opacity="0.6"/>
  <ellipse id="blush-right" cx="718" cy="844" rx="34" ry="20" fill="#F2A184" opacity="0.6"/>
  <path id="nose" d="M558,840 L602,840 C604,858 586,872 580,872 C574,872 556,858 558,840 Z" fill="#E8916F"/>
  <g id="paws" fill="#F6C58A"><ellipse cx="502" cy="926" rx="54" ry="38"/><ellipse cx="648" cy="926" rx="54" ry="38"/></g>
</g>
<g id="clouds-front">
  <path d="M-40,884 C46,814 166,814 228,872 C298,808 412,808 464,874 C532,822 638,832 676,898 C750,846 868,860 908,926 L1064,952 L1064,1064 L-40,1064 Z" fill="url(#mcCloudB)"/>
  <path d="M-40,986 C50,934 170,938 228,986 C304,936 414,942 462,994 C534,950 640,960 678,1004 L1064,1032 L1064,1064 L-40,1064 Z" fill="url(#mcCloudC)"/>
</g>'''
ICONS["05-moon-cat"] = doc(defs, body)

# ─────────────────────────────── 6 · Peak & Goal ───────────────────────────────
defs = "".join([
    lg("pkSky", 0, 0, 0, 1024, [(0, "#16245C", 1), (0.5, "#1B2A66", 1), (1, "#2A2E74", 1)]),
    rg("pkGlow", 512, 470, 480, [(0, "#FFB463", 0.6), (0.42, "#F5803A", 0.28), (1, "#E2662F", 0)]),
    rg("pkSun", 512, 486, 240, [(0, "#FFE6A2", 1), (0.5, "#FBBE5A", 1), (1, "#F49B3C", 1)]),
    lg("pkFaceLit", 300, 340, 560, 1000, [(0, "#FFE7BC", 1), (0.35, "#FBB05C", 1), (1, "#EE8034", 1)]),
    lg("pkFaceDark", 520, 380, 820, 1010, [(0, "#C8603A", 1), (1, "#8C4030", 1)]),
    lg("pkBlueA", 640, 560, 1000, 1010, [(0, "#8A8EF6", 1), (0.5, "#5A5FE6", 1), (1, "#3336B4", 1)]),
    lg("pkBlueB", 800, 600, 1020, 1010, [(0, "#4E52D8", 1), (1, "#2A2D9E", 1)]),
    lg("pkSideA", 0, 640, 300, 1010, [(0, "#6E72EA", 1), (1, "#33369F", 1)]),
    lg("pkFlag", 512, 240, 640, 330, [(0, "#FBA43A", 1), (1, "#DE6B14", 1)]),
])
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#pkSky)"/>
<ellipse id="glow" cx="512" cy="470" rx="480" ry="480" fill="url(#pkGlow)"/>
<circle id="sun" cx="512" cy="486" r="232" fill="url(#pkSun)"/>
<g id="stars" fill="#FFFFFF" opacity="0.45">
  <circle cx="158" cy="176" r="4"/><circle cx="262" cy="112" r="2.5"/><circle cx="862" cy="158" r="3.5"/><circle cx="928" cy="262" r="2.5"/></g>
<g id="peaks">
  <path id="peak-side" d="M-40,1064 C40,918 130,822 208,792 C276,848 330,948 362,1064 Z" fill="url(#pkSideA)"/>
  <path id="peak-right" d="M812,552 C884,660 972,882 1016,1064 L590,1064 C650,868 742,660 812,552 Z" fill="url(#pkBlueA)"/>
  <path id="peak-right-dark" d="M812,552 C818,720 822,912 826,1064 L1016,1064 C972,882 884,660 812,552 Z" fill="url(#pkBlueB)"/>
  <path id="peak-right-cap" d="M812,552 C838,590 862,634 882,682 C848,702 806,700 776,680 C786,632 800,590 812,552 Z" fill="#CFD1FB" opacity="0.92"/>
  <path id="peak-main" d="M504,430 C616,556 786,830 876,1064 L132,1064 C222,830 392,556 504,430 Z" fill="url(#pkFaceDark)"/>
  <path id="peak-main-lit" d="M504,430 C508,560 516,846 520,1064 L132,1064 C222,830 392,556 504,430 Z" fill="url(#pkFaceLit)"/>
  <path id="peak-main-ridge" d="M504,430 C506,560 510,846 512,1064 L486,1064 C492,846 498,560 504,430 Z" fill="#FFEFD0" opacity="0.18"/>
  
</g>
<g id="flag">
  <rect id="pole" x="496" y="232" width="17" height="200" rx="8" fill="#F6B45E"/>
  <path id="pennant" d="M512,246 C554,238 598,242 634,258 C616,276 616,302 634,322 C598,334 554,336 512,328 Z" fill="url(#pkFlag)"/>
</g>'''
ICONS["06-peak-goal"] = doc(defs, body)

# ─────────────────────────────── 7 · Focus Fox ───────────────────────────────
defs = "".join([
    lg("ffSky", 0, 0, 0, 1024, [(0, "#0A0E28", 1), (0.55, "#15183A", 1), (1, "#241B३४".replace("३४", "34"), 1)]),
    rg("ffGlow", 470, 640, 520, [(0, "#F8863A", 0.42), (0.45, "#E8722F", 0.18), (1, "#D8621F", 0)]),
    lg("ffFur", 240, 220, 700, 900, [(0, "#FFB367", 1), (0.4, "#F7852F", 1), (1, "#DE6418", 1)]),
    lg("ffFurLit", 300, 240, 560, 620, [(0, "#FFD9A6", 1), (1, "#F99A45", 1)]),
    lg("ffCream", 340, 560, 640, 980, [(0, "#FFFBF0", 1), (0.5, "#FBEBD2", 1), (1, "#EFD6B2", 1)]),
    lg("ffCap", 230, 300, 660, 400, [(0, "#FFA94F", 1), (0.45, "#F0771F", 1), (1, "#D55B12", 1)]),
])
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#ffSky)"/>
<ellipse id="glow" cx="470" cy="640" rx="520" ry="520" fill="url(#ffGlow)"/>
{star4(780, 268, 62, 0.32, "#FFD36B", "sparkle")}
<g id="motes" fill="#F0803A" opacity="0.75"><circle cx="862" cy="470" r="8"/><circle cx="806" cy="560" r="5"/><circle cx="700" cy="204" r="5"/></g>
<g id="fox">
  <path id="tail" d="M212,762 C118,762 48,830 48,910 C48,986 112,1040 200,1040 C280,1040 332,986 332,910 C332,830 288,762 212,762 Z" fill="url(#ffFur)"/>
  <path id="tail-tip" d="M104,828 C66,866 56,920 76,964 C118,958 154,926 174,884 C154,852 130,834 104,828 Z" fill="url(#ffCream)"/>
  <path id="body" d="M288,1024 C288,872 386,784 510,784 C638,784 734,872 734,1024 Z" fill="url(#ffFur)"/>
  <path id="chest" d="M394,1024 C394,908 446,854 512,854 C580,854 632,908 632,1024 Z" fill="url(#ffCream)"/>
  <path id="ear-left" d="M212,392 C204,268 234,214 288,226 C338,238 386,300 406,382 Z" fill="url(#ffFur)"/>
  <path id="ear-left-inner" d="M248,372 C242,290 258,254 288,262 C316,270 348,314 364,370 Z" fill="#8E3A14"/>
  <path id="ear-right" d="M594,376 C616,294 664,236 714,226 C766,216 792,272 780,396 Z" fill="url(#ffFur)"/>
  <path id="ear-right-inner" d="M628,368 C644,312 674,270 702,262 C732,254 748,292 742,372 Z" fill="#8E3A14"/>
  <path id="head" d="M208,536 C208,396 326,318 496,318 C664,318 784,398 784,540 C784,650 716,732 616,776 C566,798 512,846 496,900 C480,846 428,798 378,776 C276,732 208,648 208,536 Z" fill="url(#ffFur)"/>
  <path id="head-lit" d="M252,490 C288,392 366,338 452,338 C370,362 302,418 268,504 Z" fill="url(#ffFurLit)" opacity="0.7"/>
  
  
  <path id="muzzle" d="M262,628 C320,606 400,614 434,644 C462,620 530,620 558,644 C594,614 672,606 730,628 C752,690 716,758 640,790 C580,816 528,846 496,900 C464,846 412,816 352,790 C276,758 240,690 262,628 Z" fill="url(#ffCream)"/>
  <g id="cap">
    <path id="cap-band" d="M214,478 C296,410 386,378 496,378 C606,378 700,410 778,474 C784,508 784,530 778,552 C702,492 606,458 496,458 C386,458 292,494 218,552 C210,528 210,500 214,478 Z" fill="url(#ffCap)"/>
    <path id="cap-lit" d="M226,480 C304,420 388,392 496,392 C602,392 690,420 764,476 C692,438 600,420 496,420 C390,420 296,440 226,480 Z" fill="#FFB874" opacity="0.32"/>
    {star4(492, 424, 30, 0.36, "#FFE9AE", "cap-star")}
    <g id="cap-knot"><ellipse cx="208" cy="528" rx="34" ry="30" fill="#E2681B"/>
      <path d="M188,556 C160,592 140,634 130,676 C164,666 194,642 214,608 Z" fill="#D45E15"/>
      <path d="M214,570 C206,612 206,652 216,690 C236,658 244,618 238,580 Z" fill="#DC6318"/></g>
  </g>
  <path id="eye-left" d="M336,598 C356,630 396,632 420,602" fill="none" stroke="#3A2010" stroke-width="19" stroke-linecap="round"/>
  <path id="eye-right" d="M576,600 C596,632 636,632 660,602" fill="none" stroke="#3A2010" stroke-width="19" stroke-linecap="round"/>
  <ellipse id="nose" cx="496" cy="686" rx="33" ry="27" fill="#2A170B"/>
  <path id="mouth" d="M496,718 C496,748 468,756 450,740 M496,718 C496,748 524,756 542,740" fill="none" stroke="#C08A5E" stroke-width="10" stroke-linecap="round"/>
</g>'''
ICONS["07-focus-fox"] = doc(defs, body)

# ─────────────────────────────── 8 · Abstract Star ───────────────────────────────
defs = "".join([
    rg("asBg", 512, 470, 640, [(0, "#FFF9F0", 1), (0.6, "#F9EBDC", 1), (1, "#F2E2D2", 1)]),
    rg("asHalo", 512, 512, 330, [(0, "#F9C9A8", 0.55), (0.6, "#EFCBC0", 0.3), (1, "#E7D3E8", 0)]),
    lg("asStar", 512, 130, 512, 900, [(0, "#FFC45A", 1), (0.34, "#F98A33", 1), (0.56, "#E0729B", 1), (0.74, "#8A8CF0", 1), (1, "#4F63E2", 1)]),
    lg("asGloss", 400, 200, 560, 470, [(0, "#FFFFFF", 0.7), (1, "#FFFFFF", 0)]),
    lg("asGloss2", 430, 620, 600, 870, [(0, "#FFFFFF", 0.45), (1, "#FFFFFF", 0)]),
])
STAR = ("M512,104 C548,336 640,452 920,512 C640,572 548,688 512,920 "
        "C476,688 384,572 104,512 C384,452 476,336 512,104 Z")
body = f'''
<rect id="bg" width="1024" height="1024" fill="url(#asBg)"/>
<ellipse id="halo" cx="512" cy="512" rx="330" ry="330" fill="url(#asHalo)"/>
<path id="star-shadow" d="{STAR}" fill="#C9A28F" opacity="0.28" transform="translate(14 22)"/>
<path id="star" d="{STAR}" fill="url(#asStar)"/>
<path id="star-gloss-top" d="M512,170 C534,318 590,420 700,478 C606,462 546,414 512,342 C478,414 418,462 324,478 C434,420 490,318 512,170 Z" fill="url(#asGloss)"/>
<path id="star-gloss-bottom" d="M512,860 C492,738 418,646 318,592 C412,608 478,652 512,714 C546,652 612,608 706,592 C606,646 532,738 512,860 Z" fill="url(#asGloss2)"/>
<ellipse id="specular" cx="452" cy="330" rx="30" ry="66" transform="rotate(28 452 330)" fill="#FFFFFF" opacity="0.55"/>'''
ICONS["08-abstract-star"] = doc(defs, body)

if __name__ == "__main__":
    SVG.mkdir(parents=True, exist_ok=True); PNG.mkdir(parents=True, exist_ok=True)
    for name, s in ICONS.items():
        p = SVG / f"{name}.svg"; p.write_text(s)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1024,1024",
                        f"--screenshot={PNG / (name + '.png')}", f"file://{p}"], capture_output=True)
    print("rendered", len(ICONS))
