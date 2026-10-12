#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Render a v4l2 RAW10 (Bayer BGGR, 16-bit little-endian) capture as a PNG.

The IPU4P capture nodes hand out SBGGR10_1X10 in 16-bit containers, which no
image viewer understands. This does a half-resolution bilinear-ish debayer
(each 2x2 BGGR block -> one RGB pixel) and a percentile contrast stretch, so a
dark raw frame becomes something you can actually look at.

    ./scripts/raw2png.py front.raw front.png --width 2592 --height 1944 --frame 1

Frame 0 is usually the flat pedestal frame produced right after stream start;
use --frame 1 or later for real content.
"""

import argparse
import sys

import numpy as np
from PIL import Image


def debayer_bggr(raw):
    """BGGR 2x2 block -> one RGB pixel (half resolution)."""
    b = raw[0::2, 0::2].astype(np.float32)
    g1 = raw[0::2, 1::2].astype(np.float32)
    g2 = raw[1::2, 0::2].astype(np.float32)
    r = raw[1::2, 1::2].astype(np.float32)
    g = (g1 + g2) / 2.0
    return np.stack([r, g, b], axis=-1)


def stretch(img, lo_pct, hi_pct, gamma):
    lo = float(np.percentile(img, lo_pct))
    hi = float(np.percentile(img, hi_pct))
    if hi <= lo:
        hi = lo + 1.0
    out = np.clip((img - lo) / (hi - lo), 0.0, 1.0)
    if gamma != 1.0:
        out = np.power(out, gamma)
    return out, lo, hi


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("raw", help="RAW10 capture written by v4l2-ctl --stream-to")
    ap.add_argument("png", help="output PNG path")
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    ap.add_argument("--frame", type=int, default=1,
                    help="frame index to render (default 1; frame 0 is the warm-up frame)")
    ap.add_argument("--lo", type=float, default=0.5, help="low percentile for the stretch")
    ap.add_argument("--hi", type=float, default=99.5, help="high percentile for the stretch")
    ap.add_argument("--gamma", type=float, default=0.6, help="gamma applied after the stretch")
    ap.add_argument("--gray", action="store_true", help="write greyscale instead of colour")
    args = ap.parse_args()

    frame_size = args.width * args.height
    data = np.fromfile(args.raw, dtype="<u2")
    frames = data.size // frame_size
    if frames == 0:
        sys.exit(f"error: {args.raw} is smaller than one {args.width}x{args.height} frame")
    if args.frame >= frames:
        sys.exit(f"error: {args.raw} has {frames} frame(s); --frame {args.frame} is out of range")

    fr = data[args.frame * frame_size:(args.frame + 1) * frame_size]
    fr = fr.reshape(args.height, args.width)

    if args.gray:
        img = fr.astype(np.float32)[..., None]
        img = np.repeat(img, 3, axis=2)
    else:
        img = debayer_bggr(fr)

    img, lo, hi = stretch(img, args.lo, args.hi, args.gamma)
    out = (img * 255.0 + 0.5).astype(np.uint8)

    Image.fromarray(out).save(args.png)
    print(f"{args.png}: frame {args.frame}/{frames - 1}, "
          f"source {args.width}x{args.height}, output {out.shape[1]}x{out.shape[0]}, "
          f"sensor min={fr.min()} max={fr.max()}, stretch {lo:.0f}..{hi:.0f}")


if __name__ == "__main__":
    main()
