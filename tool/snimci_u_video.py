"""Spaja kadrove iz test/snimci_test.dart u MP4: samo ekran telefona, sa krugom na mjestu prsta.

    python tool/snimci_u_video.py <folder sa kadrovima> <izlazni folder>

Za svaki podfolder (npr. nova_narudzba) pravi <izlazni folder>/<podfolder>.mp4.
Treba Pillow i ffmpeg.
"""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

FPS = 30
FADE = 8  # kadrova da krug prsta nestane nakon podizanja


def touch_at(touches, frame):
    """Gdje je prst u kadru i koliko je vidljiv (0..1); None kad ga nema."""
    last = None
    for t in touches:
        if t["frame"] > frame:
            break
        last = t
    if last is None:
        return None
    if last["kind"] != "up":
        return last["x"], last["y"], 1.0
    gone = frame - last["frame"]
    if gone >= FADE:
        return None
    return last["x"], last["y"], 1.0 - gone / FADE


def phone(frame_png, touch):
    screen = Image.open(frame_png).convert("RGBA")
    if touch:
        x, y, alpha = touch
        layer = Image.new("RGBA", screen.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        r = 34
        d.ellipse(
            (x - r, y - r, x + r, y + r),
            fill=(15, 27, 51, int(80 * alpha)),
            outline=(15, 27, 51, int(170 * alpha)),
            width=3,
        )
        screen = Image.alpha_composite(screen, layer)

    return screen.convert("RGB")


def main(src, dst):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        sys.exit("Nema ffmpeg-a.")
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    for clip in sorted(p for p in Path(src).iterdir() if p.is_dir()):
        frames = sorted(clip.glob("*.png"))
        touches_file = clip / "dodiri.json"
        touches = json.loads(touches_file.read_text()) if touches_file.exists() else []
        with tempfile.TemporaryDirectory() as tmp:
            for i, f in enumerate(frames):
                phone(f, touch_at(touches, i)).save(f"{tmp}/{i:04d}.png")
            out = dst / f"{clip.name}.mp4"
            subprocess.run(
                [ffmpeg, "-y", "-loglevel", "error", "-framerate", str(FPS),
                 "-i", f"{tmp}/%04d.png", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                 "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-crf", "18",
                 "-movflags", "+faststart", str(out)],
                check=True,
            )
            print(f"{out} ({len(frames) / FPS:.1f} s)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
