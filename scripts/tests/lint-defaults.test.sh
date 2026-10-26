#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-defaults.py"

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_exit() {
    if [ "$2" -eq "$3" ]; then ok "$1 exits $3"; else bad "$1 exits $3, got $2"; fi
}

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3"; fi
}

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 has $3"; else bad "$1 is missing the text: $3"; fi
}

expect_no_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 lacks $3"; fi
}

run() {
    python3 "$checker" "$@" "$repo" >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
}

commit() {
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm "$1"
}

# A fresh repo whose Sources/A.swift is stdin and whose baseline holds that file's defaults.
fresh() {
    rm -rf "$repo"
    mkdir -p "$repo/Sources" "$repo/App" "$repo/Tests" "$repo/scripts"
    cat >"$repo/Sources/A.swift"
    git -C "$repo" init -q
    run --write-baseline
    commit base
}

echo "an added default"
fresh <<'SWIFT'
struct PendingWrite {
    init(row: Int, createdAt: Date = Date()) {}
}
SWIFT
expect_line "the baseline holds the existing default" "$(grep -v '^#' "$repo/scripts/lint-defaults-baseline.txt")" "PendingWrite|init|createdAt|now"
run
expect_exit "a tree that matches its baseline" "$status" 0
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct PendingWrite {
    init(
        row: Int,
        exerciseOrdinal: Int = 0,
        createdAt: Date = Date()
    ) {}
}
SWIFT
run
expect_exit "a new number default" "$status" 1
expect_line "it names the line and the default" "$out" \
    "Sources/A.swift:4: new number default, PendingWrite.init exerciseOrdinal = 0"
expect_text "it says what to do" "$out" "say why it is the safe answer with a \`// default: <reason>\` comment on its line."
expect_line "it counts" "$(tail -1 "$root/stdout")" "2 defaults, 1 new, 0 gone from the tree"

echo "every counted kind, and the kinds left out"
fresh <<'SWIFT'
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
final class Store {
    func a(x: Int? = nil, flag: Bool = false, run: () -> Void = {}, at: Date = .now) {}
    func b(cells: [String] = [], name: String = "", scale: Double = 1.5) {}
    func c(clock: any Clock = ContinuousClock(), order: Order = .forward, now: () -> Date = Date.init) {}
    func d(a: Int, b: Int) -> Bool { a == b }
}
SWIFT
run
expect_exit "seven counted defaults" "$status" 1
expect_line "nil" "$out" "Sources/A.swift:2: new nil default, Store.a x = nil"
expect_line "bool" "$out" "Sources/A.swift:2: new bool default, Store.a flag = false"
expect_line "closure" "$out" "Sources/A.swift:2: new closure default, Store.a run = {}"
expect_line "now" "$out" "Sources/A.swift:2: new now default, Store.a at = .now"
expect_line "empty collection" "$out" "Sources/A.swift:3: new empty default, Store.b cells = []"
expect_line "empty string" "$out" "Sources/A.swift:3: new empty default, Store.b name = \"\""
expect_line "number" "$out" "Sources/A.swift:3: new number default, Store.b scale = 1.5"
expect_no_text "an injected service is left out" "$out" "clock"
expect_no_text "a case is left out" "$out" "order"
expect_no_text "any other expression is left out" "$out" "Date.init"
expect_line "only the counted kinds count" "$(tail -1 "$root/stdout")" "7 defaults, 7 new, 0 gone from the tree"

echo "a comma inside a generic"
fresh <<'SWIFT'
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
final class Store {
    func a(_ m: Dictionary<String, Int> = [:], r: Result<A, B>? = nil, map: Box<(Int) -> Int, Int>? = nil) {}
    func b(pick: (Int) -> Bool = { _ in true }, n: Set<Int> = [], flag: Bool = false) {}
}
SWIFT
run
expect_exit "defaults after generic arguments" "$status" 1
expect_line "a Dictionary" "$out" "Sources/A.swift:2: new empty default, Store.a _ m = [:]"
expect_line "a Result" "$out" "Sources/A.swift:2: new nil default, Store.a r = nil"
expect_line "a closure type's arrow closes no generic" "$out" "Sources/A.swift:3: new bool default, Store.b flag = false"
expect_line "an arrow inside a generic" "$out" "Sources/A.swift:2: new nil default, Store.a map = nil"
expect_line "all six" "$(tail -1 "$root/stdout")" "6 defaults, 6 new, 0 gone from the tree"

echo "empty values, an immediately invoked closure, and a lazy var"
fresh <<'SWIFT'
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
final class Store {
    func a(x: Int? = .none, names: [String] = [String](), byID: [Int: String] = [Int: String](), ids: Set<Int> = Set(), more: Set<Int> = Set<Int>()) {}
    func b(made: Int = { 1 }()) {}
}
struct Card {
    var tint: Color? = .none
    var shared = {
        Formatter()
    }()
    var label = { 2 }()
    lazy var warm = false
}
SWIFT
run
expect_exit "nil and empty initializers" "$status" 1
expect_line ".none is nil" "$out" "Sources/A.swift:2: new nil default, Store.a x = .none"
expect_line "an empty array initializer" "$out" "Sources/A.swift:2: new empty default, Store.a names = [String]()"
expect_line "an empty dictionary initializer" "$out" "Sources/A.swift:2: new empty default, Store.a byID = [Int: String]()"
expect_line "Set()" "$out" "Sources/A.swift:2: new empty default, Store.a ids = Set()"
expect_line "Set<Int>()" "$out" "Sources/A.swift:2: new empty default, Store.a more = Set<Int>()"
expect_line "a memberwise .none" "$out" "Sources/A.swift:6: new nil default, Card.init tint = .none"
expect_no_text "an invoked closure is an expression" "$out" "made"
expect_no_text "an invoked multi-line closure is an expression" "$out" "shared"
expect_no_text "an invoked one-line closure is an expression" "$out" "label"
expect_line "a lazy var is a memberwise parameter" "$out" "Sources/A.swift:11: new bool default, Card.init warm = false"
expect_line "seven" "$(tail -1 "$root/stdout")" "7 defaults, 7 new, 0 gone from the tree"

echo "literals the lexer skips"
fresh <<'SWIFT'
SWIFT
literal() {
    printf 'enum Holder {\n%s\n}\nstruct After {\n    init(flag: Bool = false) {}\n}\n' "$2" >"$repo/Sources/$1.swift"
}
literal Regex '    static let pattern = /[^\s.,!?;:"“”()\-–—…]/'
literal Extended '    static let pattern = #/ { " /#'
literal MultiLine "$(printf '    static let pattern = #/\n      { "\n    /#')"
literal Raw "$(printf '    static let text = #"""\n        a """ b {\n        """#')"
literal Division '    static let total = items.map { $0/2 }.count/3 + [x].map { ($0)/2 }.count + (y)/3'
literal Operator '    static let total = items.map { [1].reduce($0, /) }.count/2'
literal SpacedOperator '    static let total = items.map { [1].reduce($0, / ) }.count/2'
literal EscapedSlash '    static let pattern = /1\/{/'
literal Nested '    /* outer /* inner */ func hidden(z: Int? = nil) {} */'
literal ExtendedEscape '    static let pattern = #/a\/#{/#'
literal Keyword '    static func quoted() -> Regex<Substring> { return /a"b/ }'
literal Backtick "$(printf '    static var half: Int { `default`/2 }\n    static let quarter = 1/4')"
rm "$repo/Sources/A.swift"
run
expect_exit "a type after each literal" "$status" 1
for file in Regex Extended Division Operator SpacedOperator EscapedSlash Nested Keyword ExtendedEscape; do
    expect_line "$file" "$out" "Sources/$file.swift:5: new bool default, After.init flag = false"
done
expect_line "a slash that closes no regex on its line divides" "$out" "Sources/Backtick.swift:6: new bool default, After.init flag = false"
for file in MultiLine Raw; do
    expect_line "$file" "$out" "Sources/$file.swift:7: new bool default, After.init flag = false"
done
expect_no_text "a nested block comment hides its code" "$out" "hidden"
expect_line "one each" "$(tail -1 "$root/stdout")" "12 defaults, 12 new, 0 gone from the tree"

echo "a line continued in a multi-line string"
fresh <<'SWIFT'
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct Caption {
    static let text = """
        a \
        b
        """
    func show(prefix: String? = nil) {}
    func hide(after: Int? = nil) {} // default: hiding at once is the common case
}
SWIFT
run
expect_exit "a default under the continued string" "$status" 1
expect_line "the unreasoned default is new" "$out" "Sources/A.swift:6: new nil default, Caption.show prefix = nil"
expect_no_text "the reason accepts its own line" "$out" "Caption.hide"

echo "the key's label"
fresh <<'SWIFT'
struct Log {
    func entries(for date: Date = .now, _ limit: Int = 0, subscript: Int = 1) {}
    subscript(index: Int = 0) -> Int { index }
    func card(@ViewBuilder content: () -> Text = { Text("") }) {}
}
SWIFT
expect_line "an external label" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "Log|entries|for|now"
expect_line "no external label" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "Log|entries|_|number"
expect_line "a subscript's parameter has no label" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "Log|subscript|_|number"
expect_line "an attribute is no label" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "Log|card|content|closure"
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct Log {
    func entries(for day: Date = .now, _ count: Int = 0, subscript: Int = 1) {}
    subscript(position: Int = 0) -> Int { position }
    func card(@ViewBuilder content: () -> Text = { Text("") }) {}
}
SWIFT
run
expect_exit "renamed internal names" "$status" 0

echo "a memberwise default and an init default of one name"
fresh <<'SWIFT'
struct Draft {
    var note: String?
}
SWIFT
expect_line "a memberwise key says so" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "Draft|memberwise|note|nil"
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct Draft {
    let note: String?
}
extension Draft {
    init(id: Int, note: String? = nil) { self.init(note: note) }
}
SWIFT
run
expect_exit "a memberwise default swapped for an init default" "$status" 1
expect_line "the init default is new" "$out" "Sources/A.swift:5: new nil default, Draft.init note = nil"

echo "a moved file"
fresh <<'SWIFT'
extension Theme {
    struct BoxShadow {
        init(x xOffset: CGFloat = 0, inset isInset: Bool = false) {}
    }
}
SWIFT
git -C "$repo" mv Sources/A.swift App/ThemePaint.swift
run
expect_exit "a file moved to another tree" "$status" 0
mv "$repo/App/ThemePaint.swift" "$repo/Sources/Paint.swift"
cat >"$repo/Sources/Paint.swift" <<'SWIFT'
enum Theme {
    struct BoxShadow {
        init(x xOffset: CGFloat = 0, inset isInset: Bool = false) {}
    }
}
SWIFT
run
expect_exit "a nested type moved out of an extension into its type" "$status" 0
cat >"$repo/Sources/Paint.swift" <<'SWIFT'
enum Theme {
    struct Shadow {
        init(x xOffset: CGFloat = 0, inset isInset: Bool = false) {}
    }
}
SWIFT
run
expect_exit "a default moved into another type" "$status" 1
expect_line "it is new under the new type" "$out" "Sources/Paint.swift:3: new number default, Theme.Shadow.init x xOffset = 0"
expect_line "its old key is gone" "$out" \
    "scripts/lint-defaults-baseline.txt: delete one \`Theme.BoxShadow|init|x|number\` line, since the tree no longer has that default."
expect_text "it names the rewrite for a rename" "$out" "run \`scripts/lint-defaults.py --write-baseline\` and commit the swap."
run --write-baseline
run
expect_exit "the rewritten baseline" "$status" 0

echo "a repeated key"
fresh <<'SWIFT'
struct Grid {
    func cell(row: Int, hidden: Bool = false) {}
}
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct Grid {
    func cell(row: Int, hidden: Bool = false) {}
    func cell(column: Int, hidden: Bool = false) {}
}
SWIFT
run
expect_exit "a second overload with the same label" "$status" 1
expect_line "it names one of the two" "$(tail -1 "$root/stdout")" "2 defaults, 1 new, 0 gone from the tree"

echo "a memberwise default"
fresh <<'SWIFT'
struct ActiveSetCard: View {
    let set: Int
}
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct ActiveSetCard: View {
    let set: Int
    var onTouchWhileHeld: () -> Void = {}
    var mic: SetCardMic?
    var dimmed = false
    var tint: Color = .blue
    let fixed: Bool = false
    static var shared: Bool = false
    private var pressed = false
    @State var held = false
    @Binding
    var bound: Bool?
    var label: String? {
        nil
    }
    var count: Int = 0 {
        didSet {}
    }
    var body: some View {
        Text("")
    }
}
SWIFT
run
expect_exit "stored vars a memberwise init takes" "$status" 1
expect_line "a closure" "$out" "Sources/A.swift:3: new closure default, ActiveSetCard.init onTouchWhileHeld = {}"
expect_line "an Optional with no value" "$out" "Sources/A.swift:4: new nil default, ActiveSetCard.init mic = nil (implicit)"
expect_line "an inferred type" "$out" "Sources/A.swift:5: new bool default, ActiveSetCard.init dimmed = false"
expect_line "an observed property" "$out" "Sources/A.swift:16: new number default, ActiveSetCard.init count = 0"
expect_line "nothing else" "$(tail -1 "$root/stdout")" "4 defaults, 4 new, 0 gone from the tree"
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct ActiveSetCard: View {
    var onTouchWhileHeld: () -> Void = {}
    init(onTouchWhileHeld: @escaping () -> Void) {
        self.onTouchWhileHeld = onTouchWhileHeld
    }
}
final class Holder {
    var onTouchWhileHeld: () -> Void = {}
}
SWIFT
run
expect_exit "a struct with its own init, and a class" "$status" 0

echo "a reasoned default"
fresh <<'SWIFT'
SWIFT
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct Reader {
    init(
        retrying: Bool = true, // default: a one-shot read is the exception
        entry: Entry? = nil //  default:
    ) {}
    var caption: String? // default: no caption reads as none
    /// default: a doc comment is no reason
    func load(cursor: Int? = nil) {}
}
SWIFT
run
expect_exit "a reasoned default beside unreasoned ones" "$status" 1
expect_no_text "the reason accepts its line" "$out" "retrying"
expect_no_text "the reason accepts a memberwise line" "$out" "caption"
expect_line "an empty reason is none" "$out" "Sources/A.swift:4: new nil default, Reader.init entry = nil"
expect_line "a doc comment is none" "$out" "Sources/A.swift:8: new nil default, Reader.load cursor = nil"
expect_line "a reasoned default is not counted" "$(tail -1 "$root/stdout")" "2 defaults, 2 new, 0 gone from the tree"
run --write-baseline
expect_no_text "a reasoned default stays out of the baseline" "$(cat "$repo/scripts/lint-defaults-baseline.txt")" "retrying"
fresh <<'SWIFT'
func load(retrying: Bool = true) {}
SWIFT
printf 'func load(retrying: Bool = true) {} // default: a one-shot read is the exception\n' >"$repo/Sources/A.swift"
run
expect_exit "a reason added to a baselined default" "$status" 1
expect_line "its key goes from the baseline" "$out" \
    "scripts/lint-defaults-baseline.txt: delete one \`|load|retrying|bool\` line, since the tree no longer has that default."

echo "what is read"
fresh <<'SWIFT'
SWIFT
printf 'func a(x: Int? = nil) {}\n' >"$repo/Tests/T.swift"
printf '// func b(x: Int? = nil) {}\nlet s = "func c(x: Int? = nil)"\nlet v = Foo.init(x: 1)\n' >"$repo/Sources/A.swift"
printf 'func d(x: Int? = nil) {}\n' >"$repo/App/Untracked.swift"
run
expect_exit "an untracked App file" "$status" 1
expect_line "it is read" "$out" "App/Untracked.swift:1: new nil default, d x = nil"
expect_line "Tests, comments, strings, and calls are not" "$(tail -1 "$root/stdout")" "1 defaults, 1 new, 0 gone from the tree"

echo "a replay"
fresh <<'SWIFT'
struct SheetWriteRequest {
    init(row: Int) {}
}
SWIFT
base=$(git -C "$repo" rev-parse HEAD)
cat >"$repo/Sources/A.swift" <<'SWIFT'
struct SheetWriteRequest {
    init(row: Int, headerHeldSetLogs: Bool = false) {}
}
SWIFT
commit offender
offender=$(git -C "$repo" rev-parse HEAD)
printf 'struct Other {}\n' >"$repo/Sources/A.swift"
: >"$repo/scripts/lint-defaults-baseline.txt"
run --base "$base" --rev "$offender"
expect_exit "a past commit against its base" "$status" 1
expect_line "it reads the commit, not the working tree" "$out" \
    "Sources/A.swift:2: new bool default, SheetWriteRequest.init headerHeldSetLogs = false"
run --base "$offender" --rev "$base"
expect_exit "a commit that only removes a default" "$status" 0
run --base "$offender"
expect_exit "the working tree against a commit" "$status" 0

echo "usage and failures"
run --rev "$base"
expect_exit "--rev with no --base" "$status" 64
run --write-baseline --base "$base"
expect_exit "--write-baseline with --base" "$status" 64
python3 "$checker" --base >/dev/null 2>&1
expect_exit "--base with no value" "$?" 64
run --fast
expect_exit "an unknown option" "$status" 64
expect_text "it prints the usage" "$err" "usage: scripts/lint-defaults.py [ROOT]"
run --base no-such-rev
expect_exit "an unknown rev" "$status" 2
expect_text "it says git failed" "$err" "error: git ls-tree -r --name-only failed"
rm "$repo/scripts/lint-defaults-baseline.txt"
run
expect_exit "a missing baseline" "$status" 2
expect_text "it names the baseline" "$err" "error: scripts/lint-defaults-baseline.txt cannot be read"
expect_text "it never passes unchecked" "$err" "fails rather than pass unchecked"
expect_no_text "it prints no traceback" "$err" "Traceback"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
