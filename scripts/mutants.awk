# Prints the --diff mutants of one Swift file, one TSV row per mutant:
#   path  line  op  before  after  mutated_line
#
#   awk -v path=Sources/X.swift -v changed=LINES_FILE [-v platform=macOS|iOS -v compiledOut=FILE] \
#       -f scripts/mutants.awk Sources/X.swift
#
# With platform, a row on a line inside an #if branch that platform compiles out is appended to
# compiledOut instead. Only os(...), canImport(UIKit), and canImport(AppKit), each alone or negated,
# decide a branch; any other condition leaves its branches compiled in.
#
# LINES_FILE holds the changed line numbers, one per line. Each op
# (bool, compare, logic, negate, return, const) yields at most one mutant per line, at its first
# match in a masked copy of the line where string literals and comments are blanked. Binary
# operators match with one space each side, which swift-format guarantees, so generics, `->`,
# `===`, `..<`, and `<<` never match.

BEGIN {
    if (path == "" || changed == "") {
        print "usage: awk -v path=REL -v changed=LINES_FILE -f mutants.awk FILE" > "/dev/stderr"
        exit 2
    }
    while ((getline n < changed) > 0) want[n] = 1
    close(changed)
    MASK = "\001"
    IN = 1; OUT = 0; UNKNOWN = -1
    blockDepth = 0
    inMultiline = 0
    multilineHashes = ""
    DIGITS = "0123456789"
    IDENT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_" DIGITS
    NOT_BEFORE_LITERAL = IDENT ".$"
    boolCount = split("true false", boolFrom, " ")
    split("false true", boolTo, " ")
    compareCount = split(" == | != | < | <= | > | >= ", compareFrom, "|")
    split(" != | == | <= | < | >= | > ", compareTo, "|")
    logicFrom[1] = " && "; logicTo[1] = " || "
    logicFrom[2] = " || "; logicTo[2] = " && "
}

function hashes(count,    s) {
    s = ""
    while (count-- > 0) s = s "#"
    return s
}

# macOS awk splits UTF-8 by byte, and a regex test on a lone lead byte aborts it, so single
# characters are tested by lookup.
function inSet(c, set) { return c != "" && index(set, c) > 0 }

function skipString(s, i, closeHashes,    n, c, j) {
    n = length(s)
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && substr(s, i + 1, length(closeHashes)) == closeHashes) {
            j = i + 1 + length(closeHashes)
            if (substr(s, j, 1) == "(") { i = skipInterpolation(s, j + 1); continue }
            i = j + 1
            continue
        }
        if (c == "\"" && substr(s, i + 1, length(closeHashes)) == closeHashes)
            return i + 1 + length(closeHashes)
        i++
    }
    return n + 1
}

function skipInterpolation(s, i,    n, c, depth, k) {
    n = length(s)
    depth = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") { i = skipString(s, i + 1, ""); continue }
        if (c == "#") {
            k = i
            while (substr(s, k, 1) == "#") k++
            if (substr(s, k, 1) == "\"") { i = skipString(s, k + 1, hashes(k - i)); continue }
        }
        if (c == "(") depth++
        if (c == ")" && --depth == 0) return i + 1
        i++
    }
    return n + 1
}

function mask(s,    n, i, c, out, k, h, end, rest) {
    n = length(s)
    out = ""
    i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (blockDepth > 0) {
            if (substr(s, i, 2) == "/*") { blockDepth++; out = out MASK MASK; i += 2; continue }
            if (substr(s, i, 2) == "*/") { blockDepth--; out = out MASK MASK; i += 2; continue }
            out = out MASK
            i++
            continue
        }
        if (inMultiline) {
            if (substr(s, i, 3 + length(multilineHashes)) == "\"\"\"" multilineHashes) {
                inMultiline = 0
                end = i + 3 + length(multilineHashes)
            } else {
                end = i + 1
            }
            while (i < end) { out = out MASK; i++ }
            continue
        }
        if (substr(s, i, 2) == "//") { while (i <= n) { out = out MASK; i++ }; break }
        if (substr(s, i, 2) == "/*") { blockDepth = 1; out = out MASK MASK; i += 2; continue }
        k = i
        while (substr(s, k, 1) == "#") k++
        if (substr(s, k, 1) != "\"") {
            out = out c
            i++
            continue
        }
        h = hashes(k - i)
        rest = substr(s, k + 3)
        if (substr(s, k, 3) == "\"\"\"" && rest ~ /^[ \t]*$/) {
            inMultiline = 1
            multilineHashes = h
            end = n + 1
        } else {
            end = skipString(s, k + 1, h)
        }
        while (i < end) { out = out MASK; i++ }
    }
    return out
}

function emit(op, before, after, mutated,    row) {
    row = sprintf("%s\t%d\t%s\t%s\t%s\t%s", path, NR, op, before, after, mutated)
    if (compiledOutLine) print row >> compiledOut
    else print row
}

function branchOn(cond,    negated, v) {
    gsub(/[ \t]/, "", cond)
    negated = sub(/^!/, "", cond)
    if (cond ~ /^os\([A-Za-z]+\)$/) v = cond == "os(" platform ")"
    else if (cond == "canImport(UIKit)") v = platform == "iOS"
    else if (cond == "canImport(AppKit)") v = platform == "macOS"
    else return UNKNOWN
    return negated ? 1 - v : v
}

function directive(m,    t, kind, v, d) {
    t = m
    gsub(MASK, "", t)
    sub(/^[ \t]+/, "", t)
    if (t !~ /^#(if|elseif|else|endif)([^A-Za-z0-9_]|$)/) return
    kind = t
    sub(/[^A-Za-z#].*/, "", kind)
    sub(/^#(if|elseif)/, "", t)
    if (kind == "#endif") { depth--; return }
    if (kind == "#if") { depth++; earlierIn[depth] = 0; earlierUnknown[depth] = 0 }
    d = depth
    v = kind == "#else" ? IN : (platform == "" ? UNKNOWN : branchOn(t))
    if (earlierIn[d] || v == OUT) branch[d] = OUT
    else if (earlierUnknown[d] || v == UNKNOWN) branch[d] = UNKNOWN
    else branch[d] = IN
    earlierIn[d] = earlierIn[d] || branch[d] == IN
    earlierUnknown[d] = earlierUnknown[d] || branch[d] == UNKNOWN
}

function inCompiledOutBranch(    d) {
    for (d = 1; d <= depth; d++) if (branch[d] == OUT) return 1
    return 0
}

function findWord(m, word,    from, p, prev, next_) {
    from = 0
    while ((p = index(substr(m, from + 1), word)) > 0) {
        p += from
        prev = p > 1 ? substr(m, p - 1, 1) : ""
        next_ = substr(m, p + length(word), 1)
        if (!inSet(prev, NOT_BEFORE_LITERAL) && !inSet(next_, IDENT)) return p
        from = p
    }
    return 0
}

function swapFirst(op, line, m, from, to, count, isOperator,    i, p, best, b, a) {
    best = 0
    for (i = 1; i <= count; i++) {
        p = isOperator ? index(m, from[i]) : findWord(m, from[i])
        if (p > 0 && (best == 0 || p < best)) { best = p; b = from[i]; a = to[i] }
    }
    if (best == 0) return
    emit(op, trim(b), trim(a), substr(line, 1, best - 1) a substr(line, best + length(b)))
}

function trim(s) {
    gsub(/^ +| +$/, "", s)
    return s
}

function topLevelIndex(m, start, token,    n, i, c, depth) {
    n = length(m)
    depth = 0
    for (i = start; i <= n; i++) {
        c = substr(m, i, 1)
        if (c == "(" || c == "[") depth++
        else if (c == ")" || c == "]") depth--
        else if (depth == 0 && substr(m, i, length(token)) == token) return i
    }
    return 0
}

function bindsOrLists(maskedCondition) {
    return maskedCondition ~ /(^|[^A-Za-z0-9_])(let|var|case) / || topLevelIndex(maskedCondition, 1, ", ") > 0
}

function negate(line, m,    lead, start, brace, cond) {
    lead = match(m, /[^ ]/)
    if (substr(m, lead, 3) == "if ") start = lead + 3
    else if (substr(m, lead, 10) == "} else if ") start = lead + 10
    else return
    brace = topLevelIndex(m, start, " {")
    if (brace <= start || bindsOrLists(substr(m, start, brace - start))) return
    cond = substr(line, start, brace - start)
    emit("negate", "if " cond " {", "if !(" cond ") {", substr(line, 1, start - 1) "!(" cond ")" substr(line, brace))
}

function forceReturn(line, m,    lead, start, stop, cond) {
    lead = match(m, /[^ ]/)
    if (substr(m, lead, 6) != "guard ") return
    start = lead + 6
    stop = topLevelIndex(m " ", start, " else ")
    if (stop <= start || bindsOrLists(substr(m, start, stop - start))) return
    cond = substr(line, start, stop - start)
    emit("return", "guard " cond " else", "guard false else", substr(line, 1, start - 1) "false" substr(line, stop))
}

function bumpConstant(line, m,    n, i, j, k, prev, intPart, literal) {
    n = length(m)
    i = 1
    while (i <= n) {
        if (!inSet(substr(m, i, 1), DIGITS)) { i++; continue }
        prev = i > 1 ? substr(m, i - 1, 1) : ""
        j = i
        while (inSet(substr(m, j, 1), DIGITS "_")) j++
        k = j
        if (substr(m, j, 1) == "." && inSet(substr(m, j + 1, 1), DIGITS)) {
            k = j + 1
            while (inSet(substr(m, k, 1), DIGITS "_")) k++
        }
        if (!inSet(prev, NOT_BEFORE_LITERAL) && !inSet(substr(m, k, 1), IDENT ":")) {
            literal = substr(line, i, k - i)
            intPart = substr(line, i, j - i)
            gsub(/_/, "", intPart)
            intPart = sprintf("%.0f", intPart + 1) substr(line, j, k - j)
            emit("const", literal, intPart, substr(line, 1, i - 1) intPart substr(line, k))
            return
        }
        i = k
    }
}

function skipLine(line, m,    t, code) {
    t = line
    sub(/^[ \t]+/, "", t)
    if (t ~ /^#(if|else|elseif|endif)([^A-Za-z0-9_]|$)/) return 1
    code = m
    gsub(MASK, "", code)
    sub(/^[ \t]+/, "", code)
    sub(/[ \t]+$/, "", code)
    if (code ~ /^(@[A-Za-z_][A-Za-z0-9_.]*(\([^)]*\))? *)+$/) return 1
    if (m ~ /#(available|unavailable)/) return 1
    if (m ~ /(^|[^A-Za-z0-9_.])(fatalError|precondition|assert|print)\(/) return 1
    return 0
}

{
    m = mask($0)
    directive(m)
    if (!(NR in want) || skipLine($0, m)) next
    compiledOutLine = inCompiledOutBranch()
    if (compiledOutLine && compiledOut == "") next
    swapFirst("bool", $0, m, boolFrom, boolTo, boolCount, 0)
    swapFirst("compare", $0, m, compareFrom, compareTo, compareCount, 1)
    swapFirst("logic", $0, m, logicFrom, logicTo, 2, 1)
    negate($0, m)
    forceReturn($0, m)
    bumpConstant($0, m)
}
