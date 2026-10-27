"""The names a line of Swift declares, for scripts/lint-vocabulary.py's count of kept and unrelated
declarations. The reader is lexical: it sees one line at a time, with comments and strings already
blanked, and follows only a parameter list or enum case that wraps onto later lines."""
from __future__ import annotations

import re

IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
NAMED = re.compile(
    r"\b(?:let|var|func|class|struct|enum|protocol|actor|typealias|associatedtype|for)\s+([A-Za-z_]\w*)")
BINDING = re.compile(r"\b(?:let|var)\s+")
CHAINED = re.compile(r",\s*([A-Za-z_]\w*)\s*(?::(?!:)|=(?!=))")
TUPLE = re.compile(r"\b(?:let|var|for)\s*\(([^()]*)\)")
CASE_PATTERN = re.compile(r"\bcase\s+(?:let|var)\s+[\w.]*\(([^()]*)\)")
TUPLE_TYPE = re.compile(r"(?:->|\b(?:let|var)\s+[A-Za-z_]\w*\s*:|\btypealias\s+[A-Za-z_]\w*\s*=)\s*(?=\()")
ENUM_CASE = re.compile(r"(?:^|[{;])\s*(?:indirect\s+)?case\s+(?!let\b|var\b)(?=[A-Za-z_])")
SIGNATURE = re.compile(r"(?<![.\w])(?:func\b|init[?!]?\s*[(<]|subscript\s*[(<])")
PARAMETER = re.compile(r"[(,]\s*(?:@\w+\s+)*(?:([A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:(?!:)")
PARENS = re.compile(r"\([^()]*\)")
CLOSURE = re.compile(r"\{\s*(?:\[([^\]]*)\]\s*)?(?:\(?\s*([A-Za-z_][\w\s,:.?\[\]<>]*?)\)?\s+)?in\b")


def depth_after(text: str, depth: int = 0) -> tuple[int, int]:
    """The paren depth at the end of text, starting from depth, and where it first returns to 0."""
    for at, char in enumerate(text):
        depth += (char == "(") - (char == ")")
        if depth == 0 and char == ")":
            return 0, at
    return depth, len(text)


def parameters(text: str) -> list[str]:
    """The argument labels and parameter names in a parameter list or a tuple type."""
    return [name for pair in PARAMETER.findall(text) for name in pair if name]


def top_level(text: str) -> str:
    """text with everything inside brackets blanked, so a comma there splits nothing."""
    depth, kept = 0, []
    for char in text:
        depth -= char in ")]}"
        kept.append(char if depth <= 0 else " ")
        depth += char in "([{"
    return "".join(kept)


def first_of(pieces: str, pick: int = 0) -> list[str]:
    """One identifier from each comma-separated piece: the first, or with pick -1 the last."""
    return [found[pick] for piece in pieces.split(",") if (found := IDENTIFIER.findall(piece))]


def declared(line: str) -> tuple[list[str], int]:
    """The names a line of code declares, and the paren depth of a signature or enum case it leaves
    open. It reads bindings (tuples, comma chains, and case patterns included), functions, types,
    enum cases, argument labels and parameters, tuple-type labels, and closure parameters."""
    names = NAMED.findall(line)
    if binding := BINDING.search(line):
        names += CHAINED.findall(top_level(line[binding.end():]))
    for tuple_pattern in TUPLE.finditer(line):
        names += first_of(tuple_pattern.group(1), -1)
    for case_pattern in CASE_PATTERN.finditer(line):
        names += first_of(case_pattern.group(1), -1)
    for tuple_type in TUPLE_TYPE.finditer(line):
        rest = line[tuple_type.end():]
        names += parameters(rest[:depth_after(rest)[1] + 1])
    still_open = 0
    case = ENUM_CASE.search(line)
    if case:
        rest = line[case.end():]
        names += parameters(rest)
        still_open = depth_after(rest)[0]
        while PARENS.search(rest):
            rest = PARENS.sub("", rest)
        names += first_of(rest)
    signature = SIGNATURE.search(line)
    if signature and (start := line.find("(", signature.end() - 1)) >= 0:
        still_open, close = depth_after(line[start:])
        names += parameters(line[start:start + close + 1])
    for closure in CLOSURE.finditer(line):
        captures, closure_parameters = closure.groups()
        names += [m.group(1) for m in re.finditer(r"([A-Za-z_]\w*)\s*=", captures or "")]
        names += first_of(closure_parameters or "")
    return names, still_open


def declared_lines(lines: list[str]) -> list[list[str]]:
    """What each line declares. A line inside a signature or enum case that an earlier line opened
    declares the parameters it holds before the list closes."""
    found, open_depth = [], 0
    for line in lines:
        names, still_open = declared(line)
        if open_depth:
            open_depth, close = depth_after(line, open_depth)
            names += parameters("," + line[:close])
        found.append(names)
        open_depth = open_depth or still_open
    return found
