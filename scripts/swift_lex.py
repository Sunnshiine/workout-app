"""The Swift lexing the lint scripts share, so that what counts as a comment, a string, or a
`// default:` reason cannot drift between them."""
from __future__ import annotations

import re
from dataclasses import dataclass

DEFAULT_REASON = re.compile(r"//(?!/)\s*default:\s*\S")
STRING_START = re.compile(r'(#*)("""|")')


@dataclass(frozen=True)
class Lexed:
    """`comments` maps a line index to the column and text of the `//` comment on it. `spans`
    holds the start and end of every comment and of every literal's body, the body never
    including an interpolation's code, with True for a comment."""

    comments: dict[int, tuple[int, str]]
    spans: list[tuple[int, int, bool]]

    def blanked(self, text: str, literals: bool) -> str:
        """The text with every comment, and with `literals` every literal body, turned to spaces,
        keeping each offset and newline."""
        out = list(text)
        for start, end, comment in self.spans:
            if comment or literals:
                for k in range(start, end):
                    if out[k] != "\n":
                        out[k] = " "
        return "".join(out)


def lex(text: str) -> Lexed:
    """A `//` inside a string or a block comment is no comment, a block comment nests, and a `\\(`
    in a string reopens code up to its `)`."""
    comments = {}
    spans: list[tuple[int, int, bool]] = []
    frames: list[tuple[str, int, int]] = []
    line = column = i = 0
    n = len(text)
    while i < n:
        kind, value, start = frames[-1] if frames else ("code", 0, 0)
        if text[i] == "\n":
            line, column, i = line + 1, 0, i + 1
            if kind == "string" and value >= 0:
                frames.pop()
                spans.append((start, i - 1, False))
            continue
        step = 1
        if kind == "block":
            if text.startswith("/*", i):
                frames.append(("block", 0, start))
                step = 2
            elif text.startswith("*/", i):
                frames.pop()
                step = 2
                if not frames or frames[-1][0] != "block":
                    spans.append((start, i + 2, True))
        elif kind == "string":
            hashes = abs(value) - 1
            close = ('"""' if value < 0 else '"') + "#" * hashes
            escape = "\\" + "#" * hashes
            if text.startswith(escape + "(", i):
                spans.append((start, i, False))
                frames.append(("code", 1, 0))
                step = len(escape) + 1
            elif text.startswith(escape, i):
                step = len(escape) + 1
            elif text.startswith(close, i):
                frames.pop()
                spans.append((start, i, False))
                step = len(close)
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            comments[line] = (column, text[i:end])
            spans.append((i, end, True))
            column, i = column + end - i, end
            continue
        elif text.startswith("/*", i):
            frames.append(("block", 0, i))
            step = 2
        elif opened := STRING_START.match(text, i):
            hashes = len(opened.group(1))
            frames.append(("string", -(hashes + 1) if opened.group(2) == '"""' else hashes + 1, opened.end()))
            step = opened.end() - i
        elif value and text[i] in "()":
            frames[-1] = ("code", value + (1 if text[i] == "(" else -1), 0)
            if frames[-1][1] == 0:
                frames.pop()
                frames[-1] = (*frames[-1][:2], i + 1)
        column, i = column + step, i + step
    block = next((f for f in frames if f[0] == "block"), None)
    spans.extend((f[2], n, False) for f in frames if f[0] == "string")
    if block:
        spans.append((block[2], n, True))
    return Lexed(comments, spans)


def line_comments(text: str) -> dict[int, tuple[int, str]]:
    return lex(text).comments
