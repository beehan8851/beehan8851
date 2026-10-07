from PIL import Image, ImageDraw, ImageFont, ImageFilter
import pathlib
HERE = pathlib.Path(__file__).resolve().parents[3] / "design" / "ember-sky" / "icon" / "concepts"
def font(size, bold=False):
    for f in (["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc"]):
        try:
            ft = ImageFont.truetype(f, size)
            if bold:
                try: ft.set_variation_by_name("Bold")
                except Exception:
                    try: ft.set_variation_by_name("Semibold")
                    except Exception: pass
            return ft
        except Exception: continue
    return ImageFont.load_default()

CONCEPTS = [
    ("01-embi-awake",   "1 · Embi, uyg'oq",     "Maskotning o'zi, qat'iy nigoh, real yoritish. Brend bilan 100% mos."),
    ("02-embi-ringing", "2 · Embi jiringlayapti", "Ilovadagi 'waking' holati: keng ko'z, halqalar, uchqunlar. Eng ko'p energiya."),
    ("03-embi-mission", "3 · Embi, missiyada",  "Peshonabog' = missiya rejimi. 'Uyg'ondingmi? Endi bajar.' Eng ko'p xarakter."),
    ("04-no-zzz",       "4 · No‑Zzz belgisi",   "Sof ramz: Z chizib tashlangan. Eng jasur, eng 'stress', maskotsiz."),
    ("05-dawnbreak",    "5 · Tong yorilishi",   "Embi ufqdan ko'tarilmoqda, yorug'lik chizig'i. Eng kinematik, App Store'da ajralib turadi."),
    ("06-rooster",      "6 · Xo'roz",           "Uyg'otishning universal belgisi. Kuchli, lekin Embi brendidan chetga chiqadi."),
]

def squircle(im, size):
    im = im.convert("RGB").resize((size, size), Image.LANCZOS)
    m = Image.new("L", (size*4, size*4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size*4-1, size*4-1], radius=int(size*4*0.2237), fill=255)
    im.putalpha(m.resize((size, size), Image.LANCZOS)); return im

def placeholder(size, dark):
    im = Image.new("RGBA", (size, size), (0,0,0,0))
    d = ImageDraw.Draw(im)
    bg = (52, 54, 66, 255) if dark else (226, 224, 218, 255)
    fg = (110, 112, 126, 255) if dark else (170, 168, 160, 255)
    d.rounded_rectangle([0,0,size-1,size-1], radius=int(size*0.2237), fill=bg)
    d.ellipse([size*0.3, size*0.3, size*0.7, size*0.7], fill=fg)
    return im

def build(CONCEPTS, OUT, title, subtitle, sheet_path):
    d = None
    W = 2400; margin = 80
    ink = (31, 26, 23); mute = (120, 112, 104); paper = (246, 240, 230)
    sheet = Image.new("RGB", (W, 2140), paper)
    d = ImageDraw.Draw(sheet)
    d.text((margin, 64), title, font=font(54, True), fill=ink)
    d.text((margin, 134), subtitle, font=font(26), fill=mute)

    # Row A — large
    n = len(CONCEPTS); S = 340; gap = (W - 2*margin - n*S) // max(1, n-1); y = 210
    for i, (key, title, desc) in enumerate(CONCEPTS):
        x = margin + i*(S+gap)
        ic = squircle(Image.open(OUT/f"{key}.png"), S)
        sh = Image.new("RGBA", (S+80, S+80), (0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([40,52,S+40,S+52], radius=int(S*0.2237), fill=(0,0,0,70))
        sh = sh.filter(ImageFilter.GaussianBlur(18)); sheet.paste(sh, (x-40, y-40), sh)
        sheet.paste(ic, (x, y), ic)
        d.text((x, y+S+22), title, font=font(30, True), fill=ink)
        # wrap desc
        words = desc.split(); lines=[]; cur=""
        for w_ in words:
            t = (cur+" "+w_).strip()
            if d.textlength(t, font=font(22)) > S: lines.append(cur); cur = w_
            else: cur = t
        lines.append(cur)
        for j, ln in enumerate(lines): d.text((x, y+S+64+j*30), ln, font=font(22), fill=mute)

    # Row B — home screen, light + dark
    def home_strip(dark, y0):
        h = 330
        bg = (22, 22, 30) if dark else (236, 231, 222)
        d.rectangle([margin, y0, W-margin, y0+h], fill=bg)
        cell = (W-2*margin) // (n+2); size = 180
        label_col = (240, 240, 240) if dark else (30, 30, 30)
        items = [None] + [c[0] for c in CONCEPTS] + [None]
        for i, key in enumerate(items):
            cx = margin + i*cell + cell//2; x = cx - size//2; yy = y0 + 46
            if key is None:
                ph = placeholder(size, dark); sheet.paste(ph, (x, yy), ph); name = "Ilova"
            else:
                ic = squircle(Image.open(OUT/f"{key}.png"), size); sheet.paste(ic, (x, yy), ic); name = "Dawnwick"
            f = font(30)
            d.text((cx - d.textlength(name, font=f)/2, yy+size+18), name, font=f, fill=label_col)
        return y0 + h

    y = 850
    d.text((margin, y), "Home screen (60 pt @3x) · yorug' va qorong'i fon", font=font(28, True), fill=ink)
    y = home_strip(False, y+50); y = home_strip(True, y+16)

    # Row C — small sizes
    y += 60
    d.text((margin, y), "Kichik o'lchamlar · Spotlight 40 pt · Settings 29 pt · Notification 20 pt (@3x)", font=font(28, True), fill=ink)
    y += 60
    cell = (W-2*margin) // n
    for i, (key, *_r) in enumerate(CONCEPTS):
        x = margin + i*cell + 20; src = Image.open(OUT/f"{key}.png")
        xx = x
        for sz in (120, 87, 60):
            ic = squircle(src, sz); sheet.paste(ic, (xx, y + (120-sz)//2), ic); xx += sz + 26
    sheet.save(sheet_path, optimize=True); print(sheet.size, sheet_path)

if __name__ == "__main__":
    build(CONCEPTS, HERE / "png", "Dawnwick · app icon konseptlari",
          "6 ta yo'nalish · vektor, qo'lda qurilgan yoritish · 1024 px · 2026‑09‑12", HERE / "sheet.png")
