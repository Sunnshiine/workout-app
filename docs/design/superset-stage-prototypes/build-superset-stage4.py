#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #430.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built superset-stage4.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/superset-stage-prototypes/build-superset-stage4.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "superset-stage4.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "superset-stage4.html").write_text(out)
print(f"wrote {HERE / 'superset-stage4.html'} ({len(out)} bytes)")
