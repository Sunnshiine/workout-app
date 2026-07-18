#!/usr/bin/env python3
"""THROWAWAY PROTOTYPE tooling — issue #413.

Splices the self-contained @font-face blocks (fonts.inc.css) into the template
so the built session-stage.html renders Fraunces + Source Sans 3 over file://
for prototype:capture. Run from anywhere:

    python3 docs/design/session-stage-prototypes/build-session-stage.py
"""
from pathlib import Path

HERE = Path(__file__).parent
template = (HERE / "session-stage.template.html").read_text()
fonts = (HERE / "fonts.inc.css").read_text()
out = template.replace("/*__FONTS__*/", fonts, 1)
assert out != template, "font marker not found"
(HERE / "session-stage.html").write_text(out)
print(f"wrote {HERE / 'session-stage.html'} ({len(out)} bytes)")
