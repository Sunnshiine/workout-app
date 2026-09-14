# crap

CRAP (Change Risk Anti-Patterns) scoring for this repository's Swift production code.

```
CRAP(f) = CC(f)^2 * (1 - cov(f))^3 + CC(f)
```

`CC` is cyclomatic complexity from the source, `cov` is per-function line coverage as a fraction in
`[0, 1]` from `llvm-cov`. Lower is better. The project target is a score of 6 or less per production
function: at full coverage a function may be arbitrarily complex and still pass, and an untested
function passes only while it stays trivial.

## Usage

`scripts/crap.sh` at the repository root is the one command to run. It runs the tests with coverage,
exports lcov, builds this package (debug), and calls the executable.

```bash
scripts/crap.sh measure --top 30   # score everything, print the worst rows
scripts/crap.sh gate               # fail on new violations, worsened rows, or a stale baseline
scripts/crap.sh baseline           # rewrite tools/crap/baseline.tsv from the current report
scripts/crap.sh gate --no-test     # reuse the coverage profile from the previous run
scripts/crap.sh --help
```

Artifacts land in `.build/crap/`: `coverage.lcov`, `report.json`, and the `swift test` log. The
baseline lives at `tools/crap/baseline.tsv`.

The script and `swift test --package-path tools/crap` both build this package in debug, so they share
one build of swift-syntax in `tools/crap/.build`. The first build takes about two minutes; later runs
cost a second or two.

The scope is fixed in the script to `WorkoutTracker` and `WorkoutCLI`, minus the four paths
`Package.swift` excludes from the library target (`Views/`, `LiveActivity/`, `Sheets/GoogleAuth.swift`,
`WorkoutTrackerApp.swift`). Scope therefore equals what `swift test` instruments.

The executable is usable on its own:

```
crap measure --root <repo-root> --lcov <file> [--source <relative dir>]... [--exclude <glob>]...
             [--threshold 6] [--json <out>] [--top 25]
crap gate    --report <json> --baseline <tsv> [--threshold 6] [--tolerance 0.5]
crap baseline --report <json> --write <tsv> [--threshold 6]
```

## Rules

### Cyclomatic complexity

CC = 1 + the sum of:

- `if` and `else if`: +1 each (an `else` alone adds nothing)
- `guard`: +1
- each additional element in a condition list beyond the first (`if a, let b, c > 0` adds +2)
- `for`, `while`, `repeat`: +1 each; a `where` clause on `for` adds +1
- each `case` clause in a `switch`: +1 (`default` adds 0; a `case a, b:` clause adds 1; a `where` on a case adds +1)
- each `catch` clause: +1
- `&&` and `||`: +1 each
- ternary `? :`: +1
- `??`: +1
- Closures inside the declaration count toward it. Nested `func` declarations do not; they are separate rows.
- Nothing else counts: `do`, `defer`, `try`, `try?`, `try!`, optional chaining, `switch` itself, `break`, `continue`, `return`, `throw` all add 0.

### Identity

`name` is `TypeChain.member(labels)` where:

- TypeChain is the enclosing nominal types joined with `.`; an extension contributes the extended
  type's name as written (`Array<Foo>` -> `Array`). Top-level functions have no chain.
- Functions: `name(label1:label2:)` using argument labels (`_` for unlabeled). Operators as written.
- Initializers: `init(label:)`; failable and throwing do not change the name. Deinit: `deinit`.
- Computed properties: `prop.get`, `prop.set`, `prop.willSet`, `prop.didSet`. A property with an
  implicit getter (`var x: T { ... }`) is `x.get`.
- Subscripts: `subscript(label:).get` / `.set`.
- Nested local functions: `outer(_:).inner(_:)`; their lines and branches are excluded from the parent.
- Closures are never rows; their branches and lines belong to the enclosing declaration.
- Overloads that produce the same `name` in the same file are disambiguated by appending `@<n>`, where
  `n` is the 1-based occurrence order within the file. Every member of a duplicate group is numbered,
  so two overloads read `f(_:)@1` and `f(_:)@2`. A name that occurs once is never suffixed.
- A declaration without a body is not a row: protocol requirements, stored properties, and enum cases
  are skipped. Declarations inside `#if` clauses **are** rows, because swift-syntax parses every
  clause; they are simply unmeasured on the platform that compiled them out.

### Coverage

Per-function coverage uses `llvm-cov`'s line records (`DA:<line>,<count>` in lcov format), which is the
same line-coverage definition `llvm-cov report` prints. For a function spanning `startLine...endLine`,
minus the spans of its nested local functions:

- `linesInstrumented` = the number of DA lines in the span
- `linesCovered` = the number of those with count > 0
- `coverage` = `linesCovered / linesInstrumented`; when `linesInstrumented == 0` the function is
  **unmeasured** (typically compiled out on macOS by `#if canImport(UIKit)`, or never instrumented).
  Unmeasured rows have `coverage == nil` and `crap == nil` and are counted in `totals.unmeasured`.

CRAP is reported to one decimal.

### Readings the rules above do not state

These are the closest reading to McCabe (or to how the identity would be written by hand), chosen
where the rules are silent.

- **Condition lists on `while`.** The rules give the extra-condition rule for `if`. `while a, let b`
  has the same condition list, so each element beyond the first adds +1 there too. `repeat ... while`
  takes a single expression and adds +1 flat.
- **Operator argument labels.** "Operators as written" fixes the spelling of the member, not the
  labels. An operator declaration's parameter names are not call-site labels, so `static func == (lhs: A, rhs: A)`
  is `A.==(_:_:)`. Subscripts follow the same rule: a parameter is labelled only when it has an
  explicit second (internal) name, so `subscript(index: Int)` is `subscript(_:)` and
  `subscript(at index: Int)` is `subscript(at:)`.
- **The span of an accessor.** A property or subscript with an implicit getter spans the whole
  declaration, from `var`/`subscript` (or its first attribute) to the closing brace. With an explicit
  accessor block, each accessor spans only its own `get`/`set`/`willSet`/`didSet` declaration, so a DA
  record on the `var` line belongs to no row and is not attributed to either accessor.
- **Accessors that are neither get, set, willSet, nor didSet** (`_read`, `_modify`, `unsafeAddress`)
  are rows of kind `unknownAccessor` named with the specifier as written, for example `x._read`.
- **Type-level initializer expressions are not rows.** A closure in a stored property's initializer
  belongs to no declaration, so its branches are dropped rather than charged to a neighbour. The same
  holds for top-level code outside any declaration.
- **Nested types inside a function.** The chain is positional, so a method of a type declared inside a
  function reads `outer(_:).Local.f()`, and its span is subtracted from `outer`.
- **A baselined function that becomes unmeasured** is reported as `stale`, like one that dropped to
  the threshold. The baseline records measured violations only, so a line that no longer describes one
  must go.

## Gate semantics

`crap gate` compares the report against `baseline.tsv` and prints every finding on its own line.

- `newViolation`: measured, `crap > threshold`, not in the baseline. Fails.
- `worsened`: in the baseline and `crap > recorded + tolerance`. Fails.
- `stale`: in the baseline but missing from the report, at or below the threshold, or no longer
  measured. Fails on purpose, so the baseline only ever shrinks. The message names the exact line to
  delete.
- `improved`: in the baseline, `crap < recorded - tolerance`, and still above the threshold. Printed as
  a note suggesting `scripts/crap.sh baseline`; does not fail.

Exit codes: 0 when clean, 1 when any finding fails.

## Layout

- `Sources/CRAPKit` is the library: `SwiftFunctionScanner` (parse and count), `LCOV` (line records),
  `Scorer` (join and score), `Gate` and `Baseline` (compare and record), `SourceScan` (file discovery
  and path globs). Every stage is a pure function over value types.
- `Sources/crap` is the ArgumentParser front end.
- `Tests/CRAPKitTests` covers the rules above with literal expected values: `swift test --package-path tools/crap`.
