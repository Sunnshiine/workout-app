#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #455.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built input-block.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/input-block-prototypes/build-input-block.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "input-block.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "input-block.html").write_text(out)
print(f"wrote {HERE / 'input-block.html'} ({len(out)} bytes)")
