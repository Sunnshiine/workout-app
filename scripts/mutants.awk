# Prints the --diff mutants of one Swift file, one TSV row per mutant:
#   path  line  op  before  after  mutated_line
#
#   awk -v path=Sources/X.swift -v changed=LINES_FILE [-v platform=macOS|iOS -v compiledOut=FILE] \
#       -f scripts/mutants-scan.awk -f scripts/mutants.awk Sources/X.swift
#
# With platform, a row on a line inside an #if branch that platform compiles out is appended to
# compiledOut instead. Only os(...), canImport(UIKit), and canImport(AppKit), each alone or negated,
# decide a branch; any other condition leaves its branches compiled in.
#
# LINES_FILE holds the changed line numbers, one per line. Each op
# (bool, compare, logic, negate, return, const, result, coalesce, operand, always, clamp) yields at
# most one mutant per line, at its first match in a masked copy of the line where string literals
# and comments are blanked, and a mutant another op already made on that line is not repeated.
# Binary operators match with one space each side, which swift-format guarantees, so generics, `->`,
# `===`, `..<`, and `<<` never match.
#
# result empties `return x` to the [], [:], nil, or 0 the enclosing declaration's return type
# takes. It skips any other type, an x already empty, an x the next line continues, and a return in
# a closure. coalesce changes a literal `?? x`. operand drops the right side of the first && or ||.
# always turns the first `a == b` into true. clamp keeps the value a two-argument max or min clamps.
# No mutant leaves a closure without an anonymous argument ($0, $1...) it used.

BEGIN {
    if (path == "" || changed == "") {
        print "usage: awk -v path=REL -v changed=LINES_FILE -f mutants-scan.awk -f mutants.awk FILE" > "/dev/stderr"
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
    braceDepth = 0
    scopes = 0
    while ((getline l < ARGV[1]) > 0) source[++sourceLines] = l
    close(ARGV[1])
}

# Swift rejects a closure whose body stops using an anonymous argument. Only a closure whose braces
# sit outside the changed span can lose one, so each of those, matched by its brace's column, must
# keep every $N it used.
function dropsAnonymousArg(mutated,    n, a, pre, suf, key, k, to, count, i, args, was, now) {
    n = length($0)
    a = length(mutated)
    for (pre = 0; pre < n && pre < a && substr($0, pre + 1, 1) == substr(mutated, pre + 1, 1); pre++) ;
    for (suf = 0; suf < n - pre && suf < a - pre && substr($0, n - suf, 1) == substr(mutated, a - suf, 1); suf++) ;
    anonymousArgs(m, was)
    anonymousArgs(maskMutant(mutated), now)
    for (key in was) {
        k = key + 0
        if (k == 0 || k <= pre) to = k
        else if (k > n - suf) to = k + a - n
        else continue
        count = split(was[key], args, ",")
        for (i = 1; i <= count; i++) if (args[i] != "" && !index(now[to], "," args[i] ",")) return 1
    }
    return 0
}

function emit(op, before, after, mutated,    row) {
    if ((NR, mutated) in emitted || dropsAnonymousArg(mutated)) return
    emitted[NR, mutated] = 1
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

function swapFirst(op, line, m, from, to, count, isOperator,    i, p, best, b, a) {
    best = 0
    for (i = 1; i <= count; i++) {
        p = isOperator ? index(m, from[i]) : findWord(m, from[i])
        if (p > 0 && (best == 0 || p < best)) { best = p; b = from[i]; a = to[i] }
    }
    if (best == 0) return
    emit(op, trim(b), trim(a), substr(line, 1, best - 1) a substr(line, best + length(b)))
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

# The first column of the operand that ends just before column p, scanning left at bracket depth 0
# to a separator, a keyword, or the indentation.
function leftEdge(m, p,    i, c, depth, before) {
    depth = 0
    for (i = p - 1; i >= 1; i--) {
        c = substr(m, i, 1)
        if (c == ")" || c == "]" || c == "}") { depth++; continue }
        if (c == "(" || c == "[" || c == "{") { if (depth == 0) break; depth--; continue }
        if (depth > 0 || c != " ") continue
        before = substr(m, 1, i - 1)
        if (before ~ /^ *$/ || before ~ /(&&|\|\||,|[^!<>=]=|\?|:|(^|[^A-Za-z0-9_])(if|guard|while|return|where|case|in))$/)
            break
    }
    while (substr(m, i + 1, 1) == " ") i++
    return i + 1
}

# The last column of the operand that starts at column p, scanning right at bracket depth 0 to a
# separator, the block's opening brace, a closing bracket, or the end of the code.
function rightEdge(m, p, stopAnd,    i, c, depth, end, block) {
    end = codeEnd(m)
    block = m ~ /^ *(\} else )?(if|while|for|switch) /
    depth = 0
    for (i = p; i <= end; i++) {
        c = substr(m, i, 1)
        if (c == "(" || c == "[") { depth++; continue }
        if (c == "{" && (depth > 0 || i < end)) { depth++; continue }
        if (c == ")" || c == "]" || c == "}") { if (depth == 0) break; depth--; continue }
        if (depth == 0 && c == ":" && i == end) break
        if (depth > 0 || c != " ") continue
        if (substr(m, i, 4) == " || " || (stopAnd && substr(m, i, 4) == " && ")) break
        if (substr(m, i, 2) == " {" && (i + 1 == end || block)) break
        if (substr(m, i, 3) == " ? " || substr(m, i, 3) == " : " || substr(m, i, 5) == " else") break
        if (substr(m, i - 1, 2) == ", ") { i--; break }
    }
    while (i - 1 > p && substr(m, i - 1, 1) == " ") i--
    return i - 1
}

function declaresType(m) {
    return m ~ /(^|[^A-Za-z0-9_])(func|extension|struct|class|enum|protocol|typealias) /
}

# Pushes the return type a line's opening brace starts: "" for a Void function, an initializer, a
# closure, or any other brace but a control-flow block, which keeps its function's type. Pops the
# scopes its closing braces end.
function trackScope(m,    code, n, i, c, type, opens) {
    code = m
    gsub(MASK, "", code)
    sub(/[ \t]+$/, "", code)
    n = length(code)
    for (i = 1; i <= n; i++) {
        c = substr(code, i, 1)
        if (c == "{") braceDepth++
        else if (c == "}") braceDepth--
    }
    while (scopes > 0 && scopeDepth[scopes] > braceDepth) scopes--
    opens = 1
    if (match(code, /-> [^{]*\{$/)) {
        type = substr(code, RSTART + 3, RLENGTH - 4)
        sub(/ where .*/, "", type)
        type = trim(type)
    } else if (match(code, /(^|[ \t])var [A-Za-z_][A-Za-z0-9_]*: [^={]+ \{$/)) {
        type = substr(code, RSTART, RLENGTH - 2)
        sub(/^.*var [A-Za-z_][A-Za-z0-9_]*: /, "", type)
    } else if (code ~ /\{$/ && code ~ /(^|[^A-Za-z0-9_])(func|init|deinit|subscript|get|set|didSet|willSet)([^A-Za-z0-9_]|$)/) {
        type = ""
    } else if (code ~ /\{[^{}]* in$/) {
        type = ""
    } else if (code ~ /\{$/ && code !~ /^[ \t}]*(if|else|guard|for|while|where|repeat|switch|do|catch|defer)([^A-Za-z0-9_]|$)/) {
        type = ""
    } else {
        opens = 0
    }
    if (opens) { scopes++; scopeDepth[scopes] = braceDepth; scopeType[scopes] = type }
}

function emptyValue(type,    inner) {
    if (type ~ /\?$/) return "nil"
    if (type ~ /^\[.*\]$/) {
        inner = substr(type, 2, length(type) - 2)
        return topLevelIndex(inner, 1, ":") ? "[:]" : "[]"
    }
    if (type ~ /^(Int|Int64|Int32|UInt|Double|Float|CGFloat|TimeInterval)$/) return "0"
    return ""
}

# An expression already empty, such as 0.0, Int.zero, [ ], or [T](), would make an equivalent mutant.
function isEmpty(expr, v,    e) {
    e = expr
    gsub(/ /, "", e)
    if (e == v) return 1
    if (v == "0") return e ~ /^[0_]+(\.[0_]+)?$/ || e ~ /^[A-Za-z0-9_]*\.zero$/
    if (v == "nil") return e ~ /^(Optional(<.*>)?)?\.none$/
    return e ~ /^\[.*\]\(\)$/ || e ~ /^(Array|Dictionary)(<.*>)?\(\)$/ || e == ".init()"
}

# Whether the next line of code continues this one's expression, as a .member or a binary operator.
function continuesOnNextLine(    j, t) {
    for (j = NR + 1; j <= sourceLines; j++) {
        t = source[j]
        sub(/^[ \t]+/, "", t)
        if (t == "" || substr(t, 1, 2) == "//") continue
        return t ~ /^\.[A-Za-z_]/ || t ~ /^[-+*\/%&|^<>=!?:~.]+( |$)/
    }
    return 0
}

function emptyResult(line, m, type,    lead, end, expr, v, c) {
    lead = match(m, /[^ ]/)
    if (substr(m, lead, 7) != "return ") return
    v = emptyValue(type)
    end = codeEnd(m)
    expr = substr(m, lead + 7, end - lead - 6)
    if (v == "" || isEmpty(expr, v)) return
    c = substr(expr, length(expr), 1)
    if (closeOf("(" expr ")", 1) != length(expr) + 2 || inSet(c, "+-*/%&|<>=!?:.,([{") || continuesOnNextLine()) return
    emit("result", "return " substr(line, lead + 7, end - lead - 6), "return " v, substr(line, 1, lead + 6) v)
}

function changeDefault(line, m,    p, q, n, old, new_, c) {
    p = index(m, " ?? ")
    if (p == 0) return
    q = p + 4
    c = substr(line, q, 1)
    if (c == "\"") {
        n = q
        while (substr(m, n + 1, 1) == MASK) n++
        old = substr(line, q, n - q + 1)
        new_ = old == "\"\"" ? "\"mutant\"" : "\"\""
    } else if (inSet(c, DIGITS)) {
        n = q
        while (inSet(substr(m, n + 1, 1), DIGITS "_")) n++
        if (inSet(substr(m, n + 1, 1), IDENT ".")) return
        old = substr(line, q, n - q + 1)
        new_ = old
        gsub(/_/, "", new_)
        new_ = sprintf("%.0f", new_ + 1)
    } else if (findWord(substr(m, q), "true") == 1 || findWord(substr(m, q), "false") == 1) {
        old = substr(m, q, 4) == "true" ? "true" : "false"
        new_ = old == "true" ? "false" : "true"
        n = q + length(old) - 1
    } else {
        return
    }
    emit("coalesce", "?? " old, "?? " new_, substr(line, 1, q - 1) new_ substr(line, n + 1))
}

function dropOperand(line, m,    a, o, p, start, end) {
    a = index(m, " && ")
    o = index(m, " || ")
    p = a > 0 && (o == 0 || a < o) ? a : o
    if (p == 0) return
    start = leftEdge(m, p)
    end = rightEdge(m, p + 4, p == a)
    if (start >= p || end < p + 4) return
    emit("operand", substr(line, start, end - start + 1), substr(line, start, p - start),
        substr(line, 1, p - 1) substr(line, end + 1))
}

function alwaysEqual(line, m,    p, start, end) {
    p = index(m, " == ")
    if (p == 0 || declaresType(m)) return
    start = leftEdge(m, p)
    end = rightEdge(m, p + 4, 1)
    if (start >= p || end < p + 4) return
    emit("always", substr(line, start, end - start + 1), "true", substr(line, 1, start - 1) "true" substr(line, end + 1))
}

function dropClamp(line, m,    p, q, open, shut, inner, comma, first, second, keep, at) {
    p = findWord(m, "max")
    q = findWord(m, "min")
    if (p == 0 || substr(m, p + 3, 1) != "(") p = 0
    if (q == 0 || substr(m, q + 3, 1) != "(") q = 0
    if (p == 0 || (q > 0 && q < p)) p = q
    if (p == 0) return
    open = p + 3
    shut = closeOf(m, open)
    if (shut == 0) return
    inner = substr(m, open + 1, shut - open - 1)
    comma = topLevelIndex(inner, 1, ", ")
    if (comma == 0 || topLevelIndex(inner, comma + 2, ", ") > 0) return
    first = substr(inner, 1, comma - 1)
    second = substr(inner, comma + 2)
    at = first ~ /^-?[0-9][0-9_.]*$/ ? open + comma + 2 : open + 1
    keep = substr(line, at, at == open + 1 ? length(first) : length(second))
    if (topLevelIndex(keep, 1, " ") > 0) keep = "(" keep ")"
    emit("clamp", substr(line, p, shut - p + 1), keep, substr(line, 1, p - 1) keep substr(line, shut + 1))
}

{
    lineBlockDepth = blockDepth; lineInMultiline = inMultiline; lineMultilineHashes = multilineHashes
    m = mask($0)
    type = scopes > 0 ? scopeType[scopes] : ""
    trackScope(m)
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
    emptyResult($0, m, type)
    changeDefault($0, m)
    dropOperand($0, m)
    alwaysEqual($0, m)
    dropClamp($0, m)
}
