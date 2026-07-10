#!/usr/bin/env python3
"""In-app illustration assets + logo processing."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from gen_ui import gen

ASSETS = {
    "ink_mountains": (
        "Traditional Chinese ink-wash (shuimo) painting of layered mountain ridges with pine trees, "
        "monochrome deep-green and charcoal tones on a very dark ink-pine green background (#0F1E18), "
        "misty atmosphere, horizontal banner composition, bottom edge fades smoothly into solid dark "
        "green #0F1E18, no text, elegant minimal, high detail"
    ),
    "ink_mountains_dusk": (
        "Traditional Chinese ink-wash painting of mountain ridges at dusk, warm amber and burnt-orange "
        "wash tones mixed with charcoal ink on very dark green background (#0F1E18), setting sun glow "
        "behind ridgeline, horizontal banner, bottom edge fades into solid dark green #0F1E18, no text, "
        "serene, high detail"
    ),
}

if __name__ == "__main__":
    for name, prompt in ASSETS.items():
        gen(name, prompt, "1536x1024")
    print("ASSETS DONE")
