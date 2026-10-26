"""The Swift lexing the lint scripts share, so that what counts as a comment, a string, or a
`// default:` reason cannot drift between them."""
from __future__ import annotations

import re
from dataclasses import dataclass

DEFAULT_REASON = re.compile(r"//\s*default:\s*\S")
STRING_START = re.compile(r'(#*)("""|")')
EXTENDED_REGEX_START = re.compile(r"(#+)/")
WORD = re.compile(r"\w+$")
REGEX_AFTER_WORDS = {"return", "try", "await", "throw", "in", "case", "where", "if", "guard", "while", "else", "switch"}


@dataclass(frozen=True)
class Lexed:
    """`comments` maps a line index to the column and text of the `//` comment on it. `spans`
    holds the start and end of every comment and of every literal's body, interpolations
    included, with True for a comment."""

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


def bare_regex_end(text: str, i: int) -> int:
    """The index just past the `/` that closes a `/.../` regex literal opening at `i`, or -1 when
    the `/` there divides. As in Swift, a regex starts where an operand can, never with a space or
    a `)`, so `reduce(0, /)` passes the operator, and it closes on its own line."""
    if text[i + 1: i + 2] in ("", " ", "\t", "\n", ")"):
        return -1
    j = i - 1
    while j >= 0 and text[j] in " \t":
        j -= 1
    if j >= 0 and text[j] in ")]}\"#!":
        return -1
    word = WORD.search(text, max(0, j - 16), j + 1) if j >= 0 else None
    if word and word.end() == j + 1 and word.group() not in REGEX_AFTER_WORDS:
        return -1
    j = i + 1
    while j < len(text) and text[j] != "\n":
        if text[j] == "/":
            return j + 1
        j += 2 if text[j] == "\\" and text[j + 1: j + 2] not in ("", "\n") else 1
    return -1


def lex(text: str) -> Lexed:
    """A `//` inside a string, a regex, or a block comment is no comment, a block comment nests,
    and a `\\(` in a string reopens code up to its `)`."""
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
                frames.append(("code", 1, 0))
                step = len(escape) + 1
            elif text.startswith(escape, i):
                step = len(escape)
                # A `\` that ends a line continues the string, and the newline still ends the line.
                if text[i + step: i + step + 1] != "\n":
                    step += 1
            elif text.startswith(close, i):
                frames.pop()
                spans.append((start, i, False))
                step = len(close)
        elif kind == "regex":
            close = "/" + "#" * value
            if text.startswith(close, i):
                frames.pop()
                spans.append((start, i, False))
                step = len(close)
            elif text[i] == "\\" and text[i + 1: i + 2] not in ("", "\n"):
                step = 2
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
        elif opened := EXTENDED_REGEX_START.match(text, i):
            frames.append(("regex", len(opened.group(1)), opened.end()))
            step = opened.end() - i
        elif text[i] == "/" and (end := bare_regex_end(text, i)) > 0:
            spans.append((i + 1, end - 1, False))
            step = end - i
        elif opened := STRING_START.match(text, i):
            hashes = len(opened.group(1))
            frames.append(("string", -(hashes + 1) if opened.group(2) == '"""' else hashes + 1, opened.end()))
            step = opened.end() - i
        elif value and text[i] in "()":
            frames[-1] = ("code", value + (1 if text[i] == "(" else -1), 0)
            if frames[-1][1] == 0:
                frames.pop()
        column, i = column + step, i + step
    block = next((f for f in frames if f[0] == "block"), None)
    spans.extend((f[2], n, False) for f in frames if f[0] in ("string", "regex"))
    if block:
        spans.append((block[2], n, True))
    return Lexed(comments, spans)


def line_comments(text: str) -> dict[int, tuple[int, str]]:
    return lex(text).comments
