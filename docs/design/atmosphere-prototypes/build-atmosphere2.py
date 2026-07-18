#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #420.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built atmosphere2.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/atmosphere-prototypes/build-atmosphere.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "atmosphere2.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "atmosphere2.html").write_text(out)
print(f"wrote {HERE / 'atmosphere2.html'} ({len(out)} bytes)")
