"""PDF vizitke Šanko (šablon Navy) za štampariju.

Pravi dva fajla u marketing/:
  vizitka_<ime>_bleed.pdf     91 × 61 mm po stranici: 85 × 55 mm + 3 mm za rezanje
  vizitka_<ime>_oznake.pdf    isto, plus oznake za rezanje oko vizitke
Stranica 1 je prednja, stranica 2 zadnja strana.

Pokretanje:  python tool/vizitke_pdf.py
Podaci su u PODACI ispod. Treba Chrome i Python paket qrcode.
"""
import base64
import io
import re
import subprocess
import tempfile
import unicodedata
from pathlib import Path

import qrcode
import qrcode.image.svg
from PIL import Image

PODACI = {
    "link": "https://drive.google.com/file/d/19Ow42G8G6P0WhERN5tF3hGnTf-JBr3d-/view?usp=sharing",
    "ime": "Adem Halilović",
    "uloga": "Prodaja i podrška",
    "telefon": "+387 60 31 22 945",
    "email": "adem.halilovic@edu.fit.ba",
    "web": "",
}

ROOT = Path(__file__).resolve().parent.parent
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
W, H, BLEED = 85, 55, 3  # mm
MARK_ROOM = 8  # mm oko reza za oznake (izvan bleeda)


def b64(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode()


def logo_data() -> str:
    im = Image.open(ROOT / "assets/brand/logo.png").convert("RGBA").resize((600, 600), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def qr_svg(text: str) -> str:
    qr = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0, box_size=10)
    qr.add_data(text)
    qr.make(fit=True)
    svg = qr.make_image(image_factory=qrcode.image.svg.SvgPathImage).to_string().decode()
    svg = re.sub(r"<\?xml[^>]*>", "", svg)
    # Popuni cijeli okvir.
    svg = re.sub(r'width="[^"]*" height="[^"]*"', 'width="100%" height="100%"', svg, count=1)
    return svg


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def html(marks: bool) -> str:
    p = PODACI
    m = MARK_ROOM if marks else BLEED  # razmak od ivice stranice do reza
    pw, ph = W + 2 * m, H + 2 * m
    fonts = "".join(
        f"@font-face{{font-family:Manrope;font-weight:{w};src:url(data:font/ttf;base64,{b64(ROOT / f'assets/fonts/Manrope-{w}.ttf')})}}"
        for w in (500, 700, 800)
    )
    logo = logo_data()
    qr = qr_svg(p["link"])
    contacts = "".join(f'<div class="c">{esc(x)}</div>' for x in (p["telefon"], p["email"], p["web"]) if x)

    def crop_marks() -> str:
        if not marks:
            return ""
        out = []
        o, ln = BLEED + 0.5, MARK_ROOM - BLEED - 1  # oznaka počinje iza bleeda
        for x in (m, m + W):
            for y in (m, m + H):
                dx = -1 if x == m else 1
                dy = -1 if y == m else 1
                # vodoravna i uspravna crtica u produžetku reza
                x1 = x + dx * o
                out.append(f'<line x1="{x1}" y1="{y}" x2="{x1 + dx * ln}" y2="{y}"/>')
                y1 = y + dy * o
                out.append(f'<line x1="{x}" y1="{y1}" x2="{x}" y2="{y1 + dy * ln}"/>')
        return (f'<svg class="marks" viewBox="0 0 {pw} {ph}" width="{pw}mm" height="{ph}mm">'
                f'<g stroke="#000" stroke-width="0.25">{"".join(out)}</g></svg>')

    # Podloga ide do ivice bleeda: kutija je reza + 3 mm sa svake strane.
    bx, by = m - BLEED, m - BLEED
    bw, bh = W + 2 * BLEED, H + 2 * BLEED

    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
{fonts}
@page {{ size: {pw}mm {ph}mm; margin: 0; }}
* {{ box-sizing: border-box; margin: 0; padding: 0; -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
html, body {{ background: #fff; font-family: Manrope, sans-serif; color: #0F1B33; }}
.page {{ width: {pw}mm; height: {ph}mm; position: relative; overflow: hidden; page-break-after: always; }}
.page:last-child {{ page-break-after: auto; }}
.bg {{ position: absolute; left: {bx}mm; top: {by}mm; width: {bw}mm; height: {bh}mm; }}
.trim {{ position: absolute; left: {m}mm; top: {m}mm; width: {W}mm; height: {H}mm; }}
.marks {{ position: absolute; left: 0; top: 0; }}

.front .bg {{ background: #0F1B33; }}
.front .strip {{ position: absolute; left: {bx}mm; width: {bw}mm; top: {m + H - 1.6}mm; height: {1.6 + BLEED}mm; background: #C9A45C; }}
.front .trim {{ display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2.4mm; padding-bottom: 1.6mm; }}
.front img {{ width: 17mm; height: 17mm; border-radius: 50%; }}
.front .brand {{ font-weight: 800; font-size: 8.6mm; color: #C9A45C; line-height: 1; letter-spacing: -.02em; }}
.front .tag {{ font-weight: 500; font-size: 2.6mm; letter-spacing: .28em; text-transform: uppercase; color: rgba(255,255,255,.82); }}

.back .bg {{ background: #fff; }}
.back .strip {{ position: absolute; top: {by}mm; height: {bh}mm; left: {bx}mm; width: {1.6 + BLEED}mm; background: #0F1B33; }}
.back .trim {{ display: grid; grid-template-columns: 1fr 27mm; gap: 4mm; padding: 6mm 6mm 6mm 7.6mm; }}
.who {{ display: flex; flex-direction: column; justify-content: center; min-width: 0; }}
.name {{ font-weight: 800; font-size: 4.2mm; line-height: 1.15; }}
.role {{ font-weight: 700; font-size: 2.5mm; color: #9A7632; margin: .8mm 0 3mm; text-transform: uppercase; letter-spacing: .08em; }}
.rule {{ width: 10mm; height: .5mm; background: #C9A45C; margin-bottom: 3mm; }}
.c {{ font-weight: 500; font-size: 2.55mm; line-height: 1.65; white-space: nowrap; }}
.qrcol {{ display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1.6mm; }}
.qr {{ width: 26mm; height: 26mm; padding: 1.6mm; border: .4mm solid #0F1B33; border-radius: 2mm; background: #fff; }}
.qr svg {{ display: block; width: 100%; height: 100%; }}
.scan {{ font-weight: 800; font-size: 2.2mm; text-align: center; line-height: 1.25; }}
</style></head><body>
<div class="page front"><div class="bg"></div><div class="strip"></div>
  <div class="trim"><img src="{logo}"><div class="brand">Šanko</div><div class="tag">Digitalna knjiga šanka</div></div>{crop_marks()}</div>
<div class="page back"><div class="bg"></div><div class="strip"></div>
  <div class="trim"><div class="who"><div class="name">{esc(p["ime"])}</div><div class="role">{esc(p["uloga"])}</div><div class="rule"></div>{contacts}</div>
  <div class="qrcol"><div class="qr">{qr}</div><div class="scan">Skeniraj i pogledaj<br>video prezentaciju</div></div></div>{crop_marks()}</div>
</body></html>"""


def slug(s: str) -> str:
    s = s.replace("đ", "dj").replace("Đ", "Dj")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_").lower()


def main() -> None:
    out_dir = ROOT / "marketing"
    out_dir.mkdir(exist_ok=True)
    name = slug(PODACI["ime"])
    with tempfile.TemporaryDirectory() as tmp:
        for marks, suffix in ((False, "bleed"), (True, "oznake")):
            src = Path(tmp) / f"{suffix}.html"
            src.write_text(html(marks), encoding="utf-8")
            pdf = out_dir / f"vizitka_{name}_{suffix}.pdf"
            subprocess.run([
                CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                f"--user-data-dir={Path(tmp) / 'profil'}",
                f"--print-to-pdf={pdf}", src.as_uri(),
            ], check=True, capture_output=True)
            print(pdf)


if __name__ == "__main__":
    main()
