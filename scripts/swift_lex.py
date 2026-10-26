"""The Swift lexing the lint scripts share, so that what counts as a comment, a string, or a
`// default:` reason cannot drift between them."""
from __future__ import annotations

import re

DEFAULT_REASON = re.compile(r"//(?!/)\s*default:\s*\S")
STRING_START = re.compile(r'(#*)("""|")')


def line_comments(text: str) -> dict[int, tuple[int, str]]:
    """Maps a line index to the column and text of the `//` comment on it. A `//` inside a string
    or a block comment is no comment, and a `\\(` in a string reopens code up to its `)`."""
    comments = {}
    frames: list[tuple[str, int]] = []
    line = column = i = 0
    n = len(text)
    while i < n:
        kind, value = frames[-1] if frames else ("code", 0)
        if text[i] == "\n":
            line, column, i = line + 1, 0, i + 1
            if kind == "string" and value >= 0:
                frames.pop()
            continue
        step = 1
        if kind == "block":
            if text.startswith("/*", i):
                frames.append(("block", 0))
                step = 2
            elif text.startswith("*/", i):
                frames.pop()
                step = 2
        elif kind == "string":
            hashes = abs(value) - 1
            close = ('"""' if value < 0 else '"') + "#" * hashes
            escape = "\\" + "#" * hashes
            if text.startswith(escape + "(", i):
                frames.append(("code", 1))
                step = len(escape) + 1
            elif text.startswith(escape, i):
                step = len(escape) + 1
            elif text.startswith(close, i):
                frames.pop()
                step = len(close)
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            comments[line] = (column, text[i:end])
            column, i = column + end - i, end
            continue
        elif text.startswith("/*", i):
            frames.append(("block", 0))
            step = 2
        elif opened := STRING_START.match(text, i):
            hashes = len(opened.group(1))
            frames.append(("string", -(hashes + 1) if opened.group(2) == '"""' else hashes + 1))
            step = opened.end() - i
        elif value and text[i] in "()":
            frames[-1] = ("code", value + (1 if text[i] == "(" else -1))
            if frames[-1][1] == 0:
                frames.pop()
        column, i = column + step, i + step
    return comments
