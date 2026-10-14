"""Pretvara slike iz foldera supabase/slike u SQL skriptu supabase/slike.sql.

Upotreba:  python tool/slike_u_sql.py

Naziv fajla je naziv slike u katalogu: "KOLA.png" postaje slika "KOLA". Artikal bez slike
čiji je naziv isti kao naziv slike dobija tu sliku automatski. Skripta se može pokretati
više puta; slika sa istim nazivom se zamjenjuje novom.

Preporuka: kvadratne slike, oko 256x256, PNG ili JPG, do 50 KB po slici.
"""

import base64
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "supabase" / "slike"
TARGET = ROOT / "supabase" / "slike.sql"
MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp"}


def main():
    files = sorted(f for f in SOURCE.iterdir() if f.suffix.lower() in MIME)
    if not files:
        raise SystemExit(f"Nema slika u {SOURCE}")
    lines = [
        "-- Slike kataloga. Napravljeno skriptom tool/slike_u_sql.py; ne mijenjati ručno.",
        "-- Pokreće se u Supabase SQL Editoru, i ponovo svaki put kad se slike promijene.",
        "",
    ]
    for f in files:
        name = f.stem.replace("_", " ").strip().upper().replace("'", "''")
        data = base64.b64encode(f.read_bytes()).decode("ascii")
        lines.append(
            "insert into public.catalog_images (name, mime, data) "
            f"values ('{name}', '{MIME[f.suffix.lower()]}', '{data}') "
            "on conflict (name) do update set mime = excluded.mime, data = excluded.data;"
        )
    lines += [
        "",
        "-- Artikli bez slike dobijaju sliku istog naziva.",
        "update public.items i set image_id = c.id",
        "from public.catalog_images c",
        "where i.image_id is null and upper(trim(i.name)) = c.name;",
        "",
    ]
    TARGET.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{len(files)} slika -> {TARGET} ({TARGET.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
