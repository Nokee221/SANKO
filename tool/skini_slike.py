"""Skida slike za artikle iz Excel tabele u folder supabase/slike, pa pravi supabase/slike.sql.

Upotreba:  python tool/skini_slike.py "Obracun KORZO.xlsx" [--preskoci-postojece] [--samo KAFA GIN]

Slike se traže na Openverse (api.openverse.org), samo pod licencama koje dozvoljavaju
komercijalnu upotrebu i izmjene (CC0, CC BY, CC BY-SA, javno dobro). Autor i licenca
svake slike se upisuju u supabase/slike/IZVORI.md; to je obaveza iz licence.

Naziv slike je naziv artikla iz tabele ("TOPLA C.jpg"), da artikal uvezen iz iste tabele
dobije sliku automatski. Slike treba pregledati prije objave: pretraga ponekad pogriješi.

Potrebno:  python -m pip install openpyxl Pillow requests
"""

import argparse
import io
import json
import pathlib
import re
import sys
import time

import openpyxl
import requests
from PIL import Image, ImageOps

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOLDER = ROOT / "supabase" / "slike"
SOURCES = FOLDER / "izvori.json"
CREDITS = FOLDER / "IZVORI.md"
API = "https://api.openverse.org/v1/images/"
HEADERS = {"User-Agent": "Sanko/1.0 (katalog slika artikala)"}
SIZE = 256
MAX_BYTES = 50 * 1024

# Pojam za pretragu po nazivu iz knjige šanka; skraćenice se ne mogu naći same.
QUERIES = {
    "KAFA": "espresso cup",
    "NES ALEG": "instant coffee cup",
    "NES": "nescafe coffee",
    "KAPUCINO": "cappuccino",
    "CAJ": "cup of tea",
    "TOPLA C": "hot chocolate",
    "JAGODA": "strawberry juice",
    "JABUKA": "apple juice",
    "RIBIZLA": "blackcurrant juice",
    "BRESKVA": "peach juice",
    "DJUS": "orange juice",
    "LEDENI C": "iced tea",
    "KOLA": "coca-cola bottle",
    "FANTA": "fanta",
    "SPRITE": "sprite soda",
    "TONIK": "tonic water",
    "COCKTA": "cockta",
    "ORANGINA": "orangina",
    "RED BULL": "red bull can",
    "SENZACIJA": "fruit juice glass",
    "KISELA": "sparkling mineral water",
    "VODA": "water bottle",
    "LIMUN": "lemonade",
    "CEDEVITA": "cedevita",
    "SULTAN": "turkish tea glass",
    "SLADOLED": "ice cream cup",
    "KING": "ice cream",
    "HEINEKEN": "heineken bottle",
    "STELLA": "stella artois",
    "BECKS": "becks beer",
    "CORONA": "corona beer",
    "SOMERSBY": "somersby cider",
    "RADLER": "radler beer",
    "BAVARIA": "bavaria beer",
    "SARAJ": "sarajevsko pivo",
    "TOCENO": "draft beer glass",
    "JEGER": "jagermeister",
    "PELIN": "pelinkovac",
    "SMIRNOF": "smirnoff vodka",
    "GIN": "gin bottle",
    "RED L": "johnnie walker red label",
    "JACK": "jack daniels",
    "CHIVAS": "chivas regal",
    "VILJAM": "pear brandy",
    "SLJIVA": "slivovitz",
    "VISNJA": "cherry liqueur",
    "GRASEVINA": "white wine glass",
    "VRANAC": "red wine glass",
}

# Slike odabrane ručno na Openverse (id slike), kad prvi rezultat pretrage ne valja.
PINNED = {
    "KAFA": "81445c24-ad48-4bbf-90d6-218b14b2eaff",
    "NES": "95724dd8-5de9-4d41-901a-ff4827e2eec9",
    "NES ALEG": "977e8e7c-0bf3-4440-9259-994818d59497",
    "GIN": "cc86188c-7e94-4347-91bf-f3d1325cec74",
    "KING": "32184a61-eb3a-4f12-a776-246ff87ba2c9",
    "ORANGINA": "18981690-2137-4ed8-b44d-178ff83b5c66",
    "RADLER": "2472c7ec-a247-4d10-a229-dd2f6d84490c",
    "SARAJ": "81b0c03b-a6f9-4b67-8232-3c5c14a7340c",
    "SLADOLED": "a84a7398-c5e9-40b7-b42a-58e0739a286b",
    "SMIRNOF": "3b0edf72-27af-4d80-8cb1-86dbcb8746df",
    "VISNJA": "9fc4b750-dfa3-48c0-846c-91fe1086140b",
    "GRASEVINA": "cd4b2fd1-086e-4bfc-9b62-57f8c2f12a60",
    "TONIK": "7e7c3e4c-a955-4087-9997-f800dde2afed",
    "COCKTA": "9879bc30-229f-48d9-bb43-19ef9de435d7",
    "SLJIVA": "09b164fa-d220-403c-a1f1-34d8c113ebd5",
    "VILJAM": "4bf24272-e6ef-45d5-a53a-f04b1d7068f5",
}

# Nazivi za koje pojam nije siguran; slika se obavezno pregleda.
UNSURE = {"SULTAN", "KING", "SENZACIJA"}


def fold(text):
    return " ".join(str(text).strip().lower().translate(str.maketrans("čćšžđ", "ccszd")).split())


def number(value):
    if isinstance(value, (int, float)):
        return value
    try:
        return float(str(value).strip().replace(",", "."))
    except ValueError:
        return None


def names_from_excel(path):
    """Nazivi artikala: tabele s kolonama "Naziv" i "Cijena", i više njih jedna pored druge."""
    names = []
    workbook = openpyxl.load_workbook(path, data_only=True, read_only=True)
    for sheet in workbook.worksheets:
        blocks = []
        for row in sheet.iter_rows(values_only=True):
            heads = [fold(c) if isinstance(c, str) else "" for c in row]
            starts = [i for i, h in enumerate(heads) if h.startswith(("naziv", "artikal", "artikl", "proizvod"))]
            header = []
            for n, start in enumerate(starts):
                end = starts[n + 1] if n + 1 < len(starts) else len(heads)
                price = next((i for i in range(start + 1, end) if re.search("cijena|cena|mpc", heads[i])), None)
                if price is not None:
                    header.append((start, price))
            if header:
                blocks = header
                continue
            for start, price in blocks:
                name = row[start] if start < len(row) else None
                if not isinstance(name, str) or not re.search(r"[^\W\d_]", name):
                    continue
                name = " ".join(name.split()).upper()
                if fold(name) in {"ukupno", "total", "suma", "svega"}:
                    continue
                if price < len(row) and number(row[price]) is not None and name not in names:
                    names.append(name)
    return names


def search(query):
    response = requests.get(
        API,
        params={"q": query, "license_type": "commercial,modification", "page_size": 20, "mature": "false"},
        headers=HEADERS,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()["results"]


def relevant(result, query):
    """Bar jedna riječ pojma je u naslovu ili oznakama slike."""
    words = {w for w in re.split(r"\W+", query.lower()) if len(w) > 2}
    text = " ".join([result.get("title") or ""] + [t["name"] for t in result.get("tags") or []]).lower()
    return any(w in text for w in words)


def square_jpeg(data):
    """Kvadrat 256x256 iz sredine slike, JPEG do 50 KB."""
    image = Image.open(io.BytesIO(data))
    image = ImageOps.exif_transpose(image).convert("RGB")
    if min(image.size) < 200:
        raise ValueError("premala slika")
    image = ImageOps.fit(image, (SIZE, SIZE), Image.Resampling.LANCZOS)
    for quality in (85, 75, 65, 55):
        out = io.BytesIO()
        image.save(out, "JPEG", quality=quality, optimize=True)
        if out.tell() <= MAX_BYTES:
            return out.getvalue()
    return out.getvalue()


def fetch(name, query):
    if name in PINNED:
        response = requests.get(f"{API}{PINNED[name]}/", headers=HEADERS, timeout=30)
        response.raise_for_status()
        ordered = [response.json()]
    else:
        results = search(query)
        ordered = [r for r in results if relevant(r, query)] + [r for r in results if not relevant(r, query)]
    for result in ordered:
        for url in (result.get("url"), result.get("thumbnail")):
            if not url:
                continue
            try:
                response = requests.get(url, headers=HEADERS, timeout=30)
                response.raise_for_status()
                return square_jpeg(response.content), result
            except Exception:
                continue
    return None, None


def write_credits(sources):
    lines = [
        "# Izvori slika artikala",
        "",
        "Napravljeno skriptom tool/skini_slike.py. Licence traže da se autor navede uz sliku.",
        "",
        "| Slika | Naslov | Autor | Licenca | Izvor |",
        "|---|---|---|---|---|",
    ]
    for name in sorted(sources):
        s = sources[name]
        cell = lambda v: str(v or "").replace("|", "/")
        lines.append(
            f"| {cell(name)} | {cell(s['title'])} | {cell(s['creator'])} | "
            f"[{cell(s['license'])}]({s['license_url']}) | [link]({s['source']}) |"
        )
    CREDITS.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("excel", type=pathlib.Path)
    parser.add_argument("--preskoci-postojece", action="store_true", help="ne mijenjaj slike koje već postoje")
    parser.add_argument("--samo", nargs="+", metavar="NAZIV", help="skini ponovo samo ove artikle")
    args = parser.parse_args()

    names = names_from_excel(args.excel)
    if not names:
        raise SystemExit("U tabeli nisu pronađeni artikli (kolone 'Naziv artikla' i 'Cijena').")
    if args.samo:
        names = [n for n in names if n in {s.upper() for s in args.samo}]
    print(f"{len(names)} artikala u {args.excel.name}")

    sources = json.loads(SOURCES.read_text(encoding="utf-8")) if SOURCES.exists() else {}
    missing = []
    for name in names:
        existing = [f for f in FOLDER.glob("*") if f.stem.upper() == name and f.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp")]
        if existing and args.preskoci_postojece:
            print(f"  {name:<12} preskočeno, slika postoji")
            continue
        query = QUERIES.get(name, f"{name.lower()} drink")
        try:
            data, result = fetch(name, query)
        except requests.RequestException as e:
            data, result = None, None
            print(f"  {name:<12} greška pretrage: {e}")
        time.sleep(1)  # Openverse bez ključa dozvoljava malo upita u sekundi.
        if data is None:
            missing.append(name)
            print(f"  {name:<12} nije pronađena slika ({query})")
            continue
        for old in existing:
            old.unlink()
        (FOLDER / f"{name}.jpg").write_bytes(data)
        sources[name] = {
            "query": query,
            "title": result.get("title"),
            "creator": result.get("creator"),
            "license": f"CC {result['license'].upper()} {result.get('license_version') or ''}".strip()
            if result["license"] not in ("cc0", "pdm")
            else result["license"].upper(),
            "license_url": result.get("license_url"),
            "source": result.get("foreign_landing_url"),
        }
        flag = "  <- PROVJERITI" if name in UNSURE else ""
        print(f"  {name:<12} {len(data) // 1024:>3} KB  {result.get('title')!r}{flag}")

    SOURCES.write_text(json.dumps(sources, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    write_credits(sources)

    sys.path.insert(0, str(ROOT / "tool"))
    import slike_u_sql

    slike_u_sql.main()
    if missing:
        print("Bez slike: " + ", ".join(missing))
    print("Sljedeći korak: pokrenuti supabase/slike.sql u Supabase SQL Editoru.")


if __name__ == "__main__":
    main()
