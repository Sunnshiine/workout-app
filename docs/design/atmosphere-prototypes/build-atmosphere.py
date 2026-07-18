#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #420.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built atmosphere.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/atmosphere-prototypes/build-atmosphere.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "atmosphere.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "atmosphere.html").write_text(out)
print(f"wrote {HERE / 'atmosphere.html'} ({len(out)} bytes)")
