#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #414.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built sunbird-moments.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/sunbird-moments-prototypes/build-sunbird-moments.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "sunbird-moments.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "sunbird-moments.html").write_text(out)
print(f"wrote {HERE / 'sunbird-moments.html'} ({len(out)} bytes)")
