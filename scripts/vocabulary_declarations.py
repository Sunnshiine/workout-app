"""The names a line of Swift declares, for scripts/lint-vocabulary.py's count of kept and unrelated
declarations. The reader is a line-based regex reader, not a Swift parser: it sees one line at a
time, with comments and strings already blanked, and counts only the forms lint-vocabulary.py names.
It follows only a parameter list or enum case's parentheses that wrap onto later lines, and the
closure parameters on the line after a `{`. lint-vocabulary.py lists the forms it misses."""
from __future__ import annotations

import re

IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
FOR = r"for(?:\s+try)?(?:\s+await)?"
NAMED = re.compile(
    rf"\b(?:let|var|func|class|struct|enum|protocol|actor|typealias|associatedtype|{FOR})\s+([A-Za-z_]\w*)")
BINDING = re.compile(r"\b(?:let|var)\s+")
CHAINED = re.compile(r",\s*([A-Za-z_]\w*)\s*(?::(?!:)|=(?!=))")
NESTED = r"(?:[^()]|\([^()]*\))*"
TUPLE = re.compile(rf"\b(?:let|var|{FOR})\s*\(({NESTED})\)")
CASE_PATTERN = re.compile(r"\b(?:case|catch)\s+(?:let|var)\s+[\w.]*\(([^()]*)\)")
TUPLE_TYPE = re.compile(
    r"(?:(?:->|\b(?:let|var)\s+[A-Za-z_]\w*\s*:|\btypealias\s+[A-Za-z_]\w*\s*=)[\w\s\[<:?]*?|\bas[?!]?\s*)(?=\()")
ATTRIBUTES = r"(?:@\w+(?:\([^()]*\))?\s*)*"
ENUM_CASE = re.compile(rf"(?:^|[{{;])\s*{ATTRIBUTES}(?:indirect\s+)?case\s+(?!let\b|var\b)(?=[A-Za-z_])")
GENERICS = re.compile(
    r"(?:\b(?:func|class|struct|enum|actor|typealias)\s+\w+|\b(?:init|subscript))\s*<([^<>]*(?:<[^<>]*>[^<>]*)*)>")
SIGNATURE = re.compile(r"(?<![.\w])(?:func\b|init[?!]?\s*[(<]|subscript\s*[(<])")
PARAMETER = re.compile(rf"[(,]\s*{ATTRIBUTES}(?:([A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:(?!:)")
PARENS = re.compile(r"\([^()]*\)")
CLOSURE = re.compile(
    rf"\{{\s*{ATTRIBUTES}(?:\[([^\]]*)\]\s*)?"
    rf"(?:\(({NESTED})\)|([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*))?\s*"
    r"(?:async\b\s*)?(?:(?:re)?throws\b(?:\([^()]*\))?\s*)?(?:->[^{}]*?)?\bin\b")


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
    """text with everything inside brackets blanked, so a comma there splits nothing, and cut at a
    bracket it never opened, where the pattern a binding sits in ends."""
    depth, kept = 0, []
    for char in text:
        depth -= char in ")]}"
        if depth < 0:
            break
        kept.append(char if depth == 0 else " ")
        depth += char in "([{"
    return "".join(kept)


def first_of(pieces: str, pick: int = 0) -> list[str]:
    """One identifier from each comma-separated piece: the first, or with pick -1 the last."""
    return [found[pick] for piece in pieces.split(",") if (found := IDENTIFIER.findall(piece))]


def declared(line: str) -> tuple[list[str], int]:
    """The names a line of code declares, and the paren depth of a signature or enum case it leaves
    open. It reads bindings (tuples, comma chains, and case patterns included), functions, types,
    enum cases, generic parameters, argument labels and parameters, tuple-type labels, and closure
    parameters."""
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
    for generics in GENERICS.finditer(line):
        names += first_of(re.sub(r"<[^<>]*>", "", generics.group(1)))
    still_open = 0
    for case in ENUM_CASE.finditer(line):
        rest = outer = line[case.end():].split(";")[0]
        while PARENS.search(outer):
            outer = PARENS.sub("", outer)
        if ":" in outer.split("(")[0]:
            continue
        names += parameters(rest) + first_of(outer.split("(")[0])
        still_open = depth_after(rest)[0]
    signature = SIGNATURE.search(line)
    if signature and (start := line.find("(", signature.end() - 1)) >= 0:
        still_open, close = depth_after(line[start:])
        names += parameters(line[start:start + close + 1])
    return names + closure_parameters(line), still_open


def closure_parameters(line: str) -> list[str]:
    """The parameters and capture-list bindings of each closure that opens on line."""
    names = []
    for closure in CLOSURE.finditer(line):
        captures, parenthesized, bare = closure.groups()
        names += [m.group(1) for m in re.finditer(r"([A-Za-z_]\w*)\s*=", captures or "")]
        if parenthesized and ":" in parenthesized:
            names += parameters("(" + parenthesized)
        else:
            names += first_of(parenthesized or bare or "")
    return names


def declared_lines(lines: list[str]) -> list[list[str]]:
    """What each line declares, backticked names read bare. A line inside a signature or enum case
    that an earlier line opened declares the parameters it holds before the list closes, and a line
    after one that ends in `{` declares the closure parameters it starts with."""
    found, open_depth, after_brace = [], 0, False
    for line in (line.replace("`", "") for line in lines):
        names, still_open = declared(line)
        if after_brace and not line.lstrip().startswith("{"):
            names += closure_parameters("{" + line)
        if open_depth:
            open_depth, close = depth_after(line, open_depth)
            names += parameters("," + line[:close])
        found.append(names)
        open_depth = open_depth or still_open
        after_brace = line.rstrip().endswith("{")
    return found
