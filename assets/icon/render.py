"""Renders the icon SVGs to the PNGs flutter_launcher_icons reads.

Usage:
  pip install cairosvg
  python3 assets/icon/render.py && dart run flutter_launcher_icons
"""
from pathlib import Path

import cairosvg

SIZE = 1024
HERE = Path(__file__).parent

for name in ('foreground', 'icon'):
    cairosvg.svg2png(
        url=str(HERE / f'{name}.svg'),
        write_to=str(HERE / f'{name}.png'),
        output_width=SIZE,
        output_height=SIZE,
    )
