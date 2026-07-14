#!/usr/bin/env python3
# Throwaway builder: extracts the embedded font data URIs from the locked
# Greenhouse prototype and injects them into sunbird-role.template.html,
# producing the self-contained sunbird-role.html (wayfinder #412, question 1).
import re, pathlib

here = pathlib.Path(__file__).parent
src = (here.parent / "direction-prototypes" / "greenhouse.html").read_text()
fonts = re.findall(r"url\((data:font/woff2;base64,[^)]+)\)", src)
assert len(fonts) == 2, f"expected 2 embedded fonts, found {len(fonts)}"
fraunces, sourcesans = fonts

html = (here / "sunbird-role.template.html").read_text()
html = html.replace("__FRAUNCES__", fraunces).replace("__SOURCESANS__", sourcesans)
(here / "sunbird-role.html").write_text(html)
print("wrote sunbird-role.html", len(html), "bytes")
