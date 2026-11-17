"""Slaže vizitku na A4 za kopirnicu: 10 komada (2 × 5), jedna do druge, sa oznakama za rezanje.

Ulaz je PDF iz tool/vizitke_pdf.py (verzija _bleed, 91 × 61 mm, prednja i zadnja strana).
Stranica 1 su prednje, stranica 2 zadnje strane; mreža je centrirana, pa se pri obostranoj
štampi (okretanje po dužoj ivici) zadnje poklope sa prednjim.

Pokretanje:  python tool/vizitke_a4.py marketing/vizitka_adem_halilovic_bleed.pdf
"""
import sys
from pathlib import Path

import pymupdf

MM = 72 / 25.4
A4W, A4H = 210, 297
W, H, BLEED = 85, 55, 3
COLS, ROWS = 2, 5


def main(src_path: str) -> None:
    src = pymupdf.open(src_path)
    out = pymupdf.open()
    x0 = (A4W - COLS * W) / 2
    y0 = (A4H - ROWS * H) / 2
    for page_no in range(len(src)):
        page = out.new_page(width=A4W * MM, height=A4H * MM)
        for r in range(ROWS):
            for c in range(COLS):
                # Iz izvora uzmi rez, a bleed samo na stranama koje su na rubu mreže.
                left = BLEED if c == 0 else 0
                right = BLEED if c == COLS - 1 else 0
                top = BLEED if r == 0 else 0
                bottom = BLEED if r == ROWS - 1 else 0
                clip = pymupdf.Rect(BLEED - left, BLEED - top, BLEED + W + right, BLEED + H + bottom)
                tx, ty = x0 + c * W, y0 + r * H
                dest = pymupdf.Rect(tx - left, ty - top, tx + W + right, ty + H + bottom)
                page.show_pdf_page(dest * MM, src, page_no, clip=clip * MM)
        # Oznake za rezanje izvan bleeda, u produžetku svake linije reza.
        gap, length = BLEED + 0.5, 4.5
        shape = page.new_shape()
        for i in range(COLS + 1):
            x = x0 + i * W
            for y_edge, d in ((y0, -1), (y0 + ROWS * H, 1)):
                shape.draw_line(pymupdf.Point(x, y_edge + d * gap) * MM, pymupdf.Point(x, y_edge + d * (gap + length)) * MM)
        for j in range(ROWS + 1):
            y = y0 + j * H
            for x_edge, d in ((x0, -1), (x0 + COLS * W, 1)):
                shape.draw_line(pymupdf.Point(x_edge + d * gap, y) * MM, pymupdf.Point(x_edge + d * (gap + 8), y) * MM)
        shape.finish(color=(0, 0, 0), width=0.25 * MM)
        shape.commit()
    dst = Path(src_path).with_name(Path(src_path).stem.replace("_bleed", "") + "_A4_10kom.pdf")
    out.save(dst, deflate=True, garbage=3)
    print(dst)


if __name__ == "__main__":
    main(sys.argv[1])
