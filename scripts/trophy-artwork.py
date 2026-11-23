#!/usr/bin/env python3
"""Generate and bundle the 1st/2nd/3rd place trophy art (see artwork/trophies/README.md).

    FAL_KEY=... scripts/trophy-artwork.py plan                 # prompts and the cost, no network
    FAL_KEY=... scripts/trophy-artwork.py run --out DIR        # fal -> DIR/place<N>-<name>.png (spends money)
    scripts/trophy-artwork.py publish --from DIR               # masters + bundled 512 px WebP data assets

FAL_KEY comes from the environment only: never pass it on a command line or commit it.
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENDPOINT = "https://fal.run/openai/gpt-image-2.6/flare/text-to-image"
COST_PER_IMAGE = 0.05  # USD, high quality 1024x1024 (the 2.5 flare price; check fal's page before a big batch)

# The frozen style. Change it only to regenerate the whole set, so all three places match.
PLACES = {
    1: ("gold", "warm polished gold with bright highlights, a small crown-like sparkle"),
    2: ("silver", "cool polished silver with soft blue-white highlights"),
    3: ("bronze", "warm burnished bronze with copper highlights"),
}
PROMPT = (
    "A single premium achievement trophy cup, {look}. Glossy 3D render, soft studio lighting, "
    "subtle rim light, rounded friendly proportions like a game reward, two curved handles, "
    "stepped base with a blank plaque, the numeral {n} embossed large and crisp on the cup. "
    "Front view, centered, fills the frame with a little margin. "
    "No other text. No background, no floor, no shadow outside the object."
)
SETTINGS = {
    "image_size": {"width": 1024, "height": 1024},
    "background": "transparent",
    "quality": "high",
    "output_format": "png",
    "num_images": 1,
}
BUNDLED_PX = 512
CATALOG = ROOT / "CommitStandingsiOS" / "Assets.xcassets"
MASTERS = ROOT / "artwork" / "trophies" / "masters"


def prompt_for(place):
    name, look = PLACES[place]
    return PROMPT.format(look=look, n=place)


def plan(_):
    for place, (name, _look) in PLACES.items():
        print(f"{place} {name}: {prompt_for(place)}\n")
    print(f"{len(PLACES)} images, about ${len(PLACES) * COST_PER_IMAGE:.2f}")


def generate(place, out):
    key = os.environ["FAL_KEY"]
    body = json.dumps({"prompt": prompt_for(place), **SETTINGS}).encode()
    request = urllib.request.Request(
        ENDPOINT, data=body, headers={"Authorization": f"Key {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        url = json.load(response)["images"][0]["url"]
    path = out / f"place{place}-{PLACES[place][0]}.png"
    with urllib.request.urlopen(url, timeout=120) as response:
        path.write_bytes(response.read())
    return path


def run(args):
    if "FAL_KEY" not in os.environ:
        sys.exit("FAL_KEY is not set in the environment.")
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with cf.ThreadPoolExecutor(max_workers=len(PLACES)) as pool:
        for path in pool.map(lambda place: generate(place, out), PLACES):
            print("wrote", path)


def publish(args):
    from PIL import Image  # pip install pillow

    source = Path(args.source)
    MASTERS.mkdir(parents=True, exist_ok=True)
    for place, (name, _look) in PLACES.items():
        png = source / f"place{place}-{name}.png"
        subprocess.run(["cwebp", "-quiet", "-lossless", "-z", "9", str(png), "-o",
                        str(MASTERS / f"place{place}-{name}.webp")], check=True)
        small = source / f".bundled-{place}.png"
        Image.open(png).convert("RGBA").resize((BUNDLED_PX, BUNDLED_PX), Image.LANCZOS).save(small)
        dataset = CATALOG / f"Trophy{name.capitalize()}.dataset"
        dataset.mkdir(parents=True, exist_ok=True)
        subprocess.run(["cwebp", "-quiet", "-q", "92", "-alpha_q", "100", "-m", "6", str(small), "-o",
                        str(dataset / f"trophy-{name}.webp")], check=True)
        small.unlink()
        (dataset / "Contents.json").write_text(json.dumps({
            "data": [{"filename": f"trophy-{name}.webp", "idiom": "universal",
                      "universal-type-identifier": "org.webmproject.webp"}],
            "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
        print("bundled", dataset.name)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("plan").set_defaults(func=plan)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("--out", required=True)
    run_parser.set_defaults(func=run)
    publish_parser = sub.add_parser("publish")
    publish_parser.add_argument("--from", dest="source", required=True)
    publish_parser.set_defaults(func=publish)
    args = parser.parse_args()
    args.func(args)
