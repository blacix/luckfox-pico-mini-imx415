#!/usr/bin/env python3
"""Report RGB channel statistics for RKIPC JPEG snapshots using Pillow."""

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageStat
except ImportError:
    sys.exit("Missing Pillow. Install it on the host with: python3 -m pip install Pillow")


SAMPLE_SIZE = (288, 162)


def percentile(histogram, samples, percent):
    target = (samples * percent + 99) // 100
    accumulated = 0
    for value, count in enumerate(histogram):
        accumulated += count
        if accumulated >= target:
            return value
    return 255


def analyze(path):
    with Image.open(path) as source:
        source_width, source_height = source.size
        image = source.convert("RGB")
        image.thumbnail(SAMPLE_SIZE, Image.Resampling.BILINEAR)
        sample_width, sample_height = image.size
        samples = sample_width * sample_height
        means = ImageStat.Stat(image).mean
        channels = {}
        for index, name in enumerate(("red", "green", "blue")):
            histogram = image.getchannel(index).histogram()
            channels[name] = {
                "mean": round(means[index], 3),
                "p10": percentile(histogram, samples, 10),
                "p50": percentile(histogram, samples, 50),
                "p90": percentile(histogram, samples, 90),
                "min": next((i for i, n in enumerate(histogram) if n), 0),
                "max": next((i for i in range(255, -1, -1) if histogram[i]), 0),
            }
    return {
        "file": str(path),
        "source_width": source_width,
        "source_height": source_height,
        "sample_width": sample_width,
        "sample_height": sample_height,
        "samples": samples,
        "channels": channels,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path,
                        help="one or more JPEGs; for a comparison pass OFF first, ON second")
    args = parser.parse_args()

    results = []
    for path in args.images:
        if not path.is_file():
            parser.error(f"image does not exist: {path}")
        results.append(analyze(path))
    print(json.dumps(results, indent=2))

    if len(results) == 2:
        before, after = results
        delta = {
            name: round(after["channels"][name]["mean"] -
                        before["channels"][name]["mean"], 3)
            for name in ("red", "green", "blue")
        }
        print("Mean-channel change (second image minus first):")
        print(json.dumps(delta, indent=2))


if __name__ == "__main__":
    main()
