#!/usr/bin/env python3
"""Cuts the painted # out of the app icon artwork: paper becomes transparent, brush and splashes stay.

make mark  ->  App/Resources/Assets.xcassets/InkhashMark.imageset/InkhashMark.png and Website/mark.png
See ADR 0066. Needs Pillow and NumPy.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

src, out = sys.argv[1:3]
rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255

# The paper behind each pixel: the brightest colour nearby, smoothed so the brush itself drops out.
paper_image = Image.fromarray((rgb * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(61)).filter(ImageFilter.GaussianBlur(60))
paper = np.asarray(paper_image).astype(np.float32) / 255

# How much darker than its paper a pixel is. Light grain stays below the knee and becomes transparent.
darkness = 1 - (rgb / np.maximum(paper, 1e-3)).min(axis=2)
knee = np.clip((darkness - 0.13) / 0.25, 0, 1)
alpha = np.clip(darkness * 1.05, 0, 1) * knee * knee * (3 - 2 * knee)

# The colour that, laid over the paper with that alpha, gives the painted pixel back.
colour = np.clip((rgb - (1 - alpha[..., None]) * paper) / np.maximum(alpha[..., None], 1e-3), 0, 1)
mark = Image.fromarray((np.dstack([colour, alpha]) * 255).astype(np.uint8), "RGBA")

# Square around the strokes, centred, with a little air.
x0, y0, x1, y1 = Image.fromarray(((alpha > 0.3) * 255).astype(np.uint8)).getbbox()
side = max(x1 - x0, y1 - y0) + 24
left, top = (x0 + x1 - side) // 2, (y0 + y1 - side) // 2
mark.crop((left, top, left + side, top + side)).resize((512, 512), Image.LANCZOS).save(out, optimize=True)
