#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #419.

Splices the self-contained @font-face blocks (fonts.inc.css) into both
templates so the built HTML renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/greenhouse-extremes-prototypes/build.py
"""
from pathlib import Path

HERE = Path(__file__).parent
fonts = (HERE / "fonts.inc.css").read_text()
for name in ("block-grid", "exercise-history", "block-grid-scale"):
    template = (HERE / f"{name}.template.html").read_text()
    out = template.replace("/*__FONTS__*/", fonts, 1)
    assert out != template, f"font marker not found in {name}"
    (HERE / f"{name}.html").write_text(out)
    print(f"wrote {HERE / f'{name}.html'} ({len(out)} bytes)")
