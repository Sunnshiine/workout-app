# Agent-facing CLI contracts: prior art for output, state addressing, and process models

Wayfinder ticket #521 (map #519) · 2026-09-13 · Research inventory from primary
sources, docs as of this date. **This document records facts and trade-offs
only; the decisions belong to the map's grilling tickets.** One cited source per
claim; passages are quoted where the ticket asked for quotes. Where a primary
source does not answer a question, that absence is stated rather than filled in.

Terminology follows `CONTEXT.md`: Block, Week, Session, Exercise, Set, Set Log,
Move On, Superset, Current Session.

---

## Summary (answer-first)

Shopify's article describes *what* their headless CLI lets agents do — "inspect
the state of the app, navigate between different sections, and perform actions"
— and *why* (accessibility-tree/screenshot loops cost "several minutes" per
check), but says nothing about state loading or reset, output format, or an
event stream; deeper dives are promised, not published. The mature agent-consumed
CLIs converge on a small set of practices rather than one format: a
machine-readable mode that is explicitly stability-guaranteed and separate from
the human one (`git --porcelain`, `git` plumbing, `gh --json`), field selection
at the call site so callers never parse prose (`gh --json <fields>`, `kubectl
-o jsonpath`, `docker inspect --format`), one-JSON-object-per-line for streams
with a discriminator field and a "new fields may be added" forward-compatibility
contract (`cargo`, `rustc`, Claude Code `stream-json`, Codex `--json`), a
final terminal record that carries the outcome (`build-finished`, Claude's
`result`, Codex's `turn.completed`), and a small documented exit-code
vocabulary. Errors are reported on the exit code plus either a structured object
in the same stream (Kubernetes `Status`, Claude `result` with `is_error`) or
stderr for diagnostics (Codex streams progress to stderr, rustc emits JSON
diagnostics to stderr). Timestamps, where present, are RFC 3339 strings
(Kubernetes) or absent from the machine stream entirely (cargo, Claude
`stream-json` carries `uuid`/`duration_ms` but no wall-clock field on result).

On process models, the documented trade-off is uniform: long-lived servers
(Bazel, Gradle) buy speed through retained in-memory state and pay in idle
lifetime, one-invocation-at-a-time locking, and stale-state risks; batch modes
(`git cat-file --batch-command`) keep one process per script while preserving
"same order as read" output; one-shot is what the two agent harnesses
themselves are built around (`claude -p` reads stdin, prints a result, and
kills background shells about five seconds after the result; Codex `exec`
prints "only the final agent message to stdout"). Agent tooling additionally
bounds output: Claude Code reads back roughly 30,000 characters of a command
by default and persists the rest to a file. On addressing, prior art offers
three coexisting forms — path-like structural addresses (`HEAD~3`,
`master:./README`, `kubectl get pod <name>`), opaque immutable IDs alongside
mutable names (Kubernetes `uid` vs `name`, Docker long/short ID vs name), and
strict resolution when a name is ambiguous (Playwright locators throw if more
than one element matches; Docker `inspect` requires `--type` to disambiguate;
Git disambiguates refs by a published precedence list). For golden tests, the
repo's existing stack already covers it: swift-snapshot-testing has a
`.lines` strategy (`Snapshotting<String, String>`, `.txt` on disk), a `.json`
strategy for `Codable` values, `assertInlineSnapshot` for in-source transcripts,
and a `.snapshots(record: .never)` Swift Testing trait that fails on missing
references in CI — which `Tests/Visual/` already uses.

---

## 1. Shopify, "Native is now the future of mobile at Shopify"

Source: Mustafa Ali, *Native is now the future of mobile at Shopify*, published
2026-09-10, <https://shopify.engineering/back-to-native>. Section "Enabling
fast feedback loops". All quotes below are from that page.

### 1.1 What the CLI exposes (quoted)

The problem statement:

> Agentic control of simulators has been a bottleneck. We found ourselves
> constantly babysitting them as they couldn't reliably build, test, and
> iterate. We built tooling to allow agents to reproduce bugs, fix them, and
> verify the fix autonomously but it was slow and brittle. React Native's hot
> module reload helps the situation but it doesn't solve it, due to simulator
> control being slow. This is primarily due to reliance on the accessibility
> tree, or screenshots to get the state of the app, take actions, and verify
> results. Agents can make code changes in seconds, but it takes them several
> minutes to test the output.

The architectural principle:

> We're fixing this by designing our app architecture to work for both humans
> and agents. The core principle here is that business logic should be
> completely decoupled from the UI and be able to run headlessly on desktop. We
> then make it available to agents via a CLI that allows them to iterate on it
> in milliseconds instead of minutes without involving simulators.

The capability list — the only sentence that enumerates what the CLI does:

> The CLI allows agents to inspect the state of the app, navigate between
> different sections, and perform actions all without needing to touch the UI.
> This enables extremely fast feedback loops and allows agents to work
> autonomously for hours at a time.

So the exposed surface is three verbs: **inspect state**, **navigate**
(sections), **perform actions**. The article's demo caption is "Navigating the
app and performing actions using the CLI".

### 1.2 What the article does *not* say

Checked against the full page text:

- **State loading / reset:** not described. No mention of fixtures, seeds,
  scenarios, snapshots, or reset commands.
- **Output format:** not described. No mention of JSON, text, or any schema.
- **Events / streaming:** not described. The word "events" does not appear in
  the section.
- **Process model:** not described (one-shot vs daemon vs REPL is not stated).

The article explicitly defers detail: "We'll share what we learn along the way,
including deeper dives into Helix, our agent-addressable architecture, and how
we're building mobile apps with agents." The term the article uses for the
overall approach is "agent-addressable architecture".

### 1.3 Relation to simulator tooling (quoted)

> When simulator interaction is needed, the CLI can connect to them via a
> remote mode and drive the UI via commands without having to inspect the
> layout or the accessibility tree. This enables blazing-fast performance and
> E2E tests.

Two facts follow: the *same* CLI has a "remote mode" that targets a simulator,
and in that mode it drives the UI "via commands" rather than through
accessibility-tree inspection — i.e. the app itself accepts commands, the CLI
does not scrape the simulator. The article does not say how the CLI connects
(socket, XCTest host, etc.).

### 1.4 Surrounding verification loop (context for "hours at a time")

The article's Helix section describes the gate each checkpoint must pass:
"each one must prove its behavior with tests, match the running app in a
visual review, survive two adversarial code reviewers, and get a human's nod
before it's committed and the next one starts." The headless CLI is positioned
as the fast inner loop inside that outer gate, not as a replacement for the
visual review.

---

## 2. Output conventions agents consume reliably

### 2.1 `gh --json` / `--jq` / `--template`

Source: `gh help formatting`,
<https://cli.github.com/manual/gh_help_formatting>.

- Field selection is mandatory and discoverable: "The `--json` flag requires a
  comma separated list of fields to fetch. To view the possible JSON field
  names for a command omit the string argument to the `--json` flag when you
  run the command."
- Post-processing is built in: "The `--jq` flag requires a string argument in
  jq query syntax, and will only print those JSON values which match the
  query." and "The `jq` utility does not need to be installed on the system to
  use this formatting directive."
- Layering rule: "Note that you must pass the `--json` flag and field names to
  use the `--jq` or `--template` flags."
- The manual page says nothing about field ordering or error shape.

Source: `pkg/cmdutil/json_flags.go` in `cli/cli` (trunk),
<https://github.com/cli/cli/blob/trunk/pkg/cmdutil/json_flags.go>.

- Encoding uses Go's standard encoder with HTML escaping off
  (`json.NewEncoder(&buf)`, `encoder.SetEscapeHTML(false)`); indentation is
  applied only when stdout is a TTY (`if ios.IsStdoutTTY() { indent = "  " }`).
  Piped output is therefore compact, single-line JSON.
- Unknown fields are a hard error that lists the valid set: `"Unknown JSON
  field: %q\nAvailable fields:\n  %s"`. Misuse is also an error: ``"cannot use
  `--jq` without specifying `--json`"``.

Source: `gh help exit-codes`,
<https://cli.github.com/manual/gh_help_exit-codes>. The documented vocabulary is
four codes: "If a command completes successfully, the exit code will be 0";
"If a command fails for any reason, the exit code will be 1"; "If a command is
running but gets cancelled, the exit code will be 2"; "If a command requires
authentication, the exit code will be 4". Individual commands may add codes.

### 2.2 Git: porcelain vs plumbing, and `--porcelain` as a stability promise

Source: `git(1)`, section "Low-level commands (plumbing)",
<https://git-scm.com/docs/git>:

> The interface (input, output, set of options and the semantics) to these
> low-level commands are meant to be a lot more stable than Porcelain level
> commands, because these commands are primarily for scripted use. The
> interface to Porcelain commands on the other hand are subject to change in
> order to improve the end user experience.

Source: *Pro Git*, "Git Internals - Plumbing and Porcelain",
<https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain>: the
plumbing subcommands "do low-level work and were designed to be chained
together UNIX-style or called from scripts", and "Many of these commands aren't
meant to be used manually on the command line, but rather to be used as
building blocks for new tools and custom scripts."

Source: `git-status(1)`, <https://git-scm.com/docs/git-status>. Note the naming
inversion: the `--porcelain` *flag* is the machine format.

- Stability promise, verbatim: "Give the output in an easy-to-parse format for
  scripts. This is similar to the short output, but will remain stable across
  Git versions and regardless of user configuration."
- Schema versioning is explicit: "The _<version>_ parameter is used to specify
  the format version. This is optional and defaults to the original version
  `v1` format." v1 "is guaranteed not to change in a backwards-incompatible way
  between Git versions or based on user configuration." v2 "adds more detailed
  information about the state of the worktree and changed items. Version 2 also
  defines an extensible set of easy to parse optional headers."
- Forward compatibility is a parser rule: "Header lines start with `#` and are
  added in response to specific command line arguments. Parsers should ignore
  headers they don't recognize."
- Config independence is enumerated: "The user's `color.status` configuration
  is not respected; color will always be off." and "The user's
  `status.relativePaths` configuration is not respected; paths shown will
  always be relative to the repository root."
- Delimiting: "There is also an alternate `-z` format recommended for machine
  parsing." With `-z`, "pathnames are printed as is and without any quoting and
  lines are terminated with a _NUL_ (ASCII 0x00) byte."
- v2 record shapes are line-typed by a leading tag: `1 <XY> <sub> <mH> <mI>
  <mW> <hH> <hI> <path>` for ordinary changes, `2 …` for renames/copies, `u …`
  for unmerged, `? <path>` untracked, `! <path>` ignored — a text analogue of a
  discriminator field.

### 2.3 `docker inspect`

Source: <https://docs.docker.com/reference/cli/docker/inspect/>.

- Default shape: "By default, `docker inspect` will render results in a JSON
  array."
- Selection: `--format` takes `'json'` ("Print in JSON format") or a Go
  template ("Print output using the given Go template"), e.g. `{{json .Config}}`
  to emit a subtree as JSON.
- Ambiguity handling: "The docker inspect command matches any type of object
  by either ID or name. In some cases multiple type of objects (for example, a
  container and a volume) exist with the same name, making the result
  ambiguous. To restrict docker inspect to a specific type of object, use the
  --type option."
- The page does not document schema versioning, field ordering, or a
  structured error object for `inspect`.

### 2.4 `kubectl -o json` and the Kubernetes API conventions

Source: kubectl reference, "Formatting output",
<https://kubernetes.io/docs/reference/kubectl/>.

- "The default output format for all `kubectl` commands is the human readable
  plain-text format." `-o json`: "Output a JSON formatted API object." `-o
  jsonpath=<template>`: "Print the fields defined in a jsonpath expression."
  `-o jsonpath-as-json=<template>`: "The same as jsonpath, but outputs valid
  JSON." `-o name`: "Print only the resource name and nothing else."
- Ordering is opt-in, not default: "To sort a list of resources, add the
  `--sort-by` flag to a supported `kubectl` command. Specify the field you want
  to sort by using the `jsonpath` expression." No default list order is
  documented on this page.

Source: Kubernetes API Conventions,
<https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md>.

- Schema versioning is in-band: every object carries `apiVersion` and `kind`;
  list kinds carry `metadata.resourceVersion` "that identifies the common
  version of the objects returned by in a list".
- Timestamps: "creationTimestamp: a string representing an RFC 3339 date of
  the date and time an object was created" and, generally, "All dates should be
  serialized as RFC3339 strings."
- Structured errors are a first-class kind (`Status`): "`status` field contains
  one of two possible values: `Success`, `Failure`"; "`message` may contain
  human-readable description of the error"; "`reason` may contain a
  machine-readable, one-word, CamelCase description of why this operation is in
  the `Failure` status. … The `reason` clarifies an HTTP status code but does
  not override it."; "`details` may contain extended data associated with the
  reason. … the data returned is not guaranteed to conform to any schema except
  that defined by the reason type."

Source: Kubernetes API Concepts, "Resource versions",
<https://kubernetes.io/docs/reference/using-api/api-concepts/>: "You must not
assume resource versions are numeric or collatable." Pagination is by an
opaque `continue` token. Neither page states a guaranteed order for list
items.

### 2.5 `cargo --message-format json` and `rustc --error-format=json`

Source: Cargo reference, "JSON messages",
<https://doc.rust-lang.org/cargo/reference/external-tools.html>.

- Shape and channel: "The output goes to stdout in the JSON object per line
  format. The `reason` field distinguishes different kinds of messages."
- Message kinds: `compiler-message`, `compiler-artifact`,
  `build-script-executed`, and `build-finished` "emitted at the end of the
  build" — a terminal record.
- Stable identity: "The `package_id` field is a unique identifier for referring
  to the package, and as the `--package` argument to many commands." (Note:
  "MSRV: 1.77 is required for `package_id` to be a Package ID Specification.
  Before that, it was opaque." — an example of an opaque ID later being given a
  documented grammar.)
- Mixed-stream caveat: "`--message-format=json` only controls Cargo and
  Rustc's output. This cannot control the output of other tools … A possible
  workaround in these situations is to only interpret a line as JSON if it
  starts with `{`."
- No timestamps are defined in the message schema.

Source: rustc book, "JSON Output", <https://doc.rust-lang.org/rustc/json.html>.

- Channel: "JSON messages are emitted one per line to stderr."
- Discriminator and forward-compat rule: "Each type of message has a
  `$message_type` field which can be used to distinguish the different formats.
  When parsing, care should be taken to be forwards-compatible with future
  changes to the format. Optional values may be `null`. New fields may be
  added. Enumerated fields like "level" or "suggestion_applicability" may add
  new values."
- Unstable parts are labelled as such: the `timings` messages are "unstable and
  subject to change" and gated behind `-Zunstable-options`.

### 2.6 NDJSON / JSON Lines event streams

Source: NDJSON spec 1.0.0 (2014-10-19), <https://github.com/ndjson/ndjson-spec>.

- "Each JSON text MUST conform to the RFC8259 standard and MUST be written to
  the stream followed by the newline character `\n` (0x0A)."
- "All serialized data MUST use the UTF8 encoding."
- "The parser MAY silently ignore empty lines, e.g. `\n\n`. This behavior MUST
  be documented and SHOULD be configurable by the user."
- The spec defines framing only; ordering, discriminators, and terminal records
  are conventions layered by each tool (§2.5, §2.7, §2.8).

### 2.7 Claude Code `--output-format json` / `stream-json`

Source: "Run Claude Code programmatically",
<https://code.claude.com/docs/en/headless>.

- Three formats: "`text` (default): plain text output"; "`json`: structured
  JSON with result, session ID, and metadata"; "`stream-json`:
  newline-delimited JSON for real-time streaming".
- Schema-constrained output: "use `--output-format json` with `--json-schema`
  and a JSON Schema definition. The response includes metadata about the
  request (session ID, usage, etc.) with the structured output in the
  `structured_output` field." An invalid schema is a start-up error.
- Stream ordering contract: the `system/init` event "is the first event in the
  stream unless startup events precede it", and "The last line of the stream is
  a `result` message with the final response text, cost, and session metadata."
- Feature detection by capability list, not version: the init event "carries
  an optional `capabilities` array of strings naming the protocol behaviors this
  Claude Code version implements … Check it to feature-detect instead of
  comparing version strings, and ignore values you don't recognize."
- Errors, stdout vs stderr: "Claude Code exits with code 0 on success and a
  non-zero code when the run fails … If you pass an invalid flag, Claude Code
  reports the error to stderr before the run starts. When a failure happens
  inside the run, such as missing authentication, Claude Code prints the
  failure as the result on stdout." SIGTERM exits 143.
- Omitted-key convention for error arrays: `plugin_errors` — "The key is
  omitted when there are no errors"; `mcp_server_errors` — "The key is omitted
  when there are no errors, so a CI gate can fail on a non-empty array."

Source: Agent SDK TypeScript reference,
<https://code.claude.com/docs/en/agent-sdk/typescript>. `SDKResultMessage` is a
discriminated union on `subtype` (`"success"` vs `"error_max_turns" |
"error_during_execution" | "error_max_budget_usd" |
"error_max_structured_output_retries"`); both arms carry `uuid`,
`session_id`, `duration_ms`, `is_error`, `num_turns`, `total_cost_usd`,
`permission_denials`; the error arm adds `errors: string[]`. There is no
wall-clock timestamp field on the result; the closest is
`request_sent_wall_ms` ("epoch milliseconds at which Claude Code dispatched the
API request, for joins against server-side timestamps").

### 2.8 Codex `exec --json`

Source: "Non-interactive mode",
<https://learn.chatgpt.com/docs/non-interactive-mode>.

- Channel split, verbatim: "While `codex exec` runs, Codex streams progress to
  `stderr` and prints only the final agent message to `stdout`. This makes it
  straightforward to redirect or pipe the final result".
- Stream mode: "When you enable `--json`, `stdout` becomes a JSON Lines (JSONL)
  stream so you can capture every event Codex emits while it's running. Event
  types include `thread.started`, `turn.started`, `turn.completed`,
  `turn.failed`, `item.*`, and `error`." Items carry their own `id`
  (`"item_1"`) and `status` (`"in_progress"`).
- Last-message sidecar: "`-o <path>`/`--output-last-message <path>` … writes
  the final message to the file and still prints it to `stdout`."
- Schema-constrained output: "use `--output-schema` to request a final response
  that conforms to a JSON Schema."
- Exit codes are not enumerated on this page; the one documented case is "If
  you configure an enabled MCP server with `required = true` and it fails to
  initialize, `codex exec` exits with an error".

### 2.9 Cross-tool table

| Concern | gh | git porcelain | docker inspect | kubectl / K8s API | cargo / rustc | Claude Code | Codex |
|---|---|---|---|---|---|---|---|
| Machine mode opt-in | `--json <fields>` | `--porcelain[=v]` | default JSON array | `-o json` | `--message-format json` | `--output-format` | `--json` |
| Schema versioning | none documented | `v1`/`v2` in flag; unknown `#` headers ignored | none documented | `apiVersion`/`kind` in-band | "new fields may be added"; unstable parts gated | `capabilities` array in `system/init` | none documented |
| Discriminator | n/a | leading line tag (`1`,`2`,`u`,`?`,`!`) | n/a | `kind` | `reason` / `$message_type` | `type` + `subtype` | `type` |
| Stable ordering | not documented | entries per path; `-z` NUL framing | array order not documented | opt-in `--sort-by`; none by default | stream order; `build-finished` last | `system/init` first, `result` last | `thread.started` … `turn.completed` |
| Timestamps | n/a | none | none documented | RFC 3339 `creationTimestamp` | none | none on result (`request_sent_wall_ms` epoch ms) | none in sample |
| Exit codes | 0/1/2/4 documented | n/a | n/a | not documented | n/a | 0 / non-zero / 143 on SIGTERM | not enumerated |
| Structured error | `Unknown JSON field` + list (stderr) | `<object> SP missing` (cat-file) | n/a | `Status{status,reason,message,details,code}` | `compiler-message` on stdout; rustc to stderr | `result{is_error,errors[]}` on stdout; flag errors on stderr | `error` event on stdout; progress on stderr |

---

## 3. Process models

### 3.1 One-shot with on-disk state (the agent harnesses' own default)

Source: <https://code.claude.com/docs/en/headless>.

- Non-interactive is a pipe: "Non-interactive mode reads stdin, so you can pipe
  data in and redirect the response out like any other command-line tool."
  "Piped stdin is capped at 10MB."
- Reproducibility lever: `--bare` "is useful for CI and scripts where you need
  the same result on every machine", and "is the recommended mode for scripted
  and SDK calls, and will become the default for `-p` in a future release."
- Daemons started by a one-shot run are killed: "If Claude starts a background
  Bash task during a `claude -p` run, for example a dev server or a watch build,
  that shell is terminated about five seconds after Claude has returned its
  final result and stdin has closed."
- Continuity is on-disk, addressed by ID: "`--resume` with a session ID …
  Claude Code finds the session by its ID in any project on this machine", and
  `--resume` also accepts "the absolute path to a session's `.jsonl` transcript
  file".

Source: <https://learn.chatgpt.com/docs/non-interactive-mode>. Codex's
equivalent is `codex exec resume --last "…"` / `codex exec resume <SESSION_ID>`.

### 3.2 Output bounds the agent host imposes

Source: Claude Code "Tools reference", Bash output limits,
<https://code.claude.com/docs/en/tools-reference>. Successful command output is
"Inline up to roughly 30,000 characters by default; past that, the path of a
file saved to the session directory and truncated past 64 MiB, plus a short
preview from the start, and Claude reads or searches the file when it needs the
rest". Failed output is "Inline up to roughly 10,000 characters; past that, a
head-and-tail excerpt of that size cut from the read-back window, with no file
path". "A command whose output passes 5 GB is killed."

Source: Claude Code "Environment variables",
<https://code.claude.com/docs/en/env-vars>. `BASH_MAX_OUTPUT_LENGTH`: "Maximum
number of characters of bash output that Claude Code reads back into a
command's result (default: 30000; maximum: 150000)". `BASH_DEFAULT_TIMEOUT_MS`
"(default: 120000, or 2 minutes)"; `BASH_MAX_TIMEOUT_MS` "(default: 600000, or
10 minutes)".

Source: Anthropic, "Writing tools for agents",
<https://www.anthropic.com/engineering/writing-tools-for-agents>. First-party
guidance on the same constraint: "tool implementations should take care to
return only high signal information back to agents"; use "pagination, range
selection, filtering, and/or truncation with sensible default parameter
values"; when truncating, "steer agents with helpful instructions"; errors
should "clearly communicate specific and actionable improvements, rather than
opaque error codes or tracebacks". The page's worked example offers a
`response_format` parameter with `"concise"` and `"detailed"` values, where
detailed responses include technical identifiers "for downstream tool calls".

### 3.3 Batch / script mode (many commands, one process)

Source: `git-cat-file(1)`, <https://git-scm.com/docs/git-cat-file>.

- Deterministic order: "`cat-file` will read objects from stdin, one per line,
  and print information about them in the same order as they have been read."
- Command language on stdin: "`--batch-command` Enter a command mode that reads
  commands and arguments from stdin." Commands are `contents <object>`, `info
  <object>`, `flush`, `mailmap (<bool>)`.
- Interactive-vs-throughput trade-off is explicit: "Normally batch output is
  flushed after each object is output, so that a process can interactively read
  and write from `cat-file`. With this option [`--buffer`], the output uses
  normal stdio buffering; this is much more efficient when invoking
  `--batch-check` or `--batch-command` on a large number of objects."
- In-band error record instead of aborting: "If a name is specified on stdin
  that cannot be resolved to an object in the repository, then `cat-file` will
  ignore any custom format and print: `<object> SP missing LF`."

### 3.4 Daemon / server

Source: Bazel, "Client/server implementation",
<https://bazel.build/run/client-server>.

- Why: "The Bazel system is implemented as a long-lived server process. This
  allows it to perform many optimizations not possible with a batch-oriented
  implementation, such as caching of BUILD files, dependency graphs, and other
  metadata from one build to the next."
- Costs: "The server process will stop after a period of inactivity (3 hours,
  by default, which can be modified using the startup option
  `--max_idle_secs`)." "Each server can handle at most one invocation at a
  time; further concurrent invocations will either block or fail-fast."

Source: Gradle, "The Gradle Daemon",
<https://docs.gradle.org/current/userguide/gradle_daemon.html>.

- "The Gradle Daemon is a long-lived, persistent process that runs in the
  background and hosts Gradle's execution engine." "The Daemon enables
  in-memory caching across builds." "The Daemon can reduce build times by
  15-75% when you build the same project repeatedly."
- Staleness/lifecycle: daemons stop when "Available system memory is low" or
  "Daemon has been idle for 3 hours"; "When a memory leak exhausts available
  heap space, the Daemon: 1. Finishes the currently running build. 2. Restarts
  before running the next build." CI opt-out is `--no-daemon` or
  `org.gradle.daemon=false`.

### 3.5 Trade-off summary (from the sources above)

| Model | Determinism | Agent-host fit | Documented cost |
|---|---|---|---|
| One-shot + on-disk state | Highest: every run starts from disk; `--bare`-style flags exist precisely to make runs identical across machines | Native fit: harnesses read stdin, bound stdout (~30k chars), kill leftover processes ~5 s after result | Cold start per call; state must be serialisable and addressable (session ID or path) |
| Batch on stdin | Output "in the same order as … read"; per-item in-band error records | Fits a single Bash call; output size scales with script length so bounds matter | Needs a mini command language; flush/buffer semantics to choose |
| Daemon / REPL | Depends on retained memory; documented stale-state and memory-leak restarts | Poor fit: harness terminates background shells; single-invocation lock; idle timeouts | Speed via cached state |

---

## 4. Stable entity addressing

### 4.1 Path-like structural addresses (Git revisions)

Source: `gitrevisions(7)`, <https://git-scm.com/docs/gitrevisions>.

- Index-relative walks: "`<rev>~<n>` … means the commit object that is the
  <n>th generation ancestor of the named commit object, following only the
  first parents"; "`<rev>^<n>` means the <n>th parent".
- Path inside a container: "`<rev>:<path>` … names the blob or tree at the given
  path in the tree-ish object named by the part before the colon."
- Search-by-content as an address: "`:/<text>` … names a commit whose commit
  message matches the specified regular expression. This name returns the
  youngest matching commit" — i.e. non-unique matches are resolved by a
  documented tie-break (youngest), not an error.
- Non-unique short IDs are rejected rather than guessed: a short hash names an
  object only "if there is no other object in your repository whose object name
  starts with dae86e."
- Name collisions across namespaces are resolved by a published precedence
  list: "When ambiguous, a `<refname>` is disambiguated by taking the first
  match in the following rules" (`$GIT_DIR/<refname>`, `refs/<refname>`,
  `refs/tags/…`, `refs/heads/…`, `refs/remotes/…`, `refs/remotes/…/HEAD`).

### 4.2 Opaque immutable ID beside a mutable name (Kubernetes, Docker)

Source: Kubernetes API Conventions (link in §2.4).

- `name`: "a string that uniquely identifies this object within the current
  namespace … This value is used in the path when retrieving an individual
  object."
- `uid`: "a unique in time and space value (typically an RFC 4122 generated
  identifier …) used to distinguish between objects with the same name that
  have been deleted and recreated".
- `resourceVersion`: "MUST be treated as opaque by clients and passed
  unmodified back to the server."

Source: Docker, "Running containers", section "Container identification",
<https://docs.docker.com/engine/containers/run/>: "You can identify a container
in three ways" — "UUID long identifier" (64 hex), "UUID short identifier"
(12 hex), and "Name". "The UUID identifier is a random ID assigned to the
container by the daemon. The daemon generates a random string name for
containers automatically. You can also define a custom name using the `--name`
flag."

Source: `docker inspect` (link in §2.3): a name shared across object types is
"ambiguous" and the caller must pass `--type`.

### 4.3 Strictness on non-unique matches (Playwright)

Source: Playwright, "Locators" → "Strictness",
<https://playwright.dev/docs/locators#strictness>.

- "Locators are strict. This means that all operations on locators that imply
  some target DOM element will throw an exception if more than one element
  matches."
- Explicit opt-out by index: "You can explicitly opt-out from strictness check
  by telling Playwright which element to use when multiple elements match,
  through locator.first(), locator.last(), and locator.nth()." With the
  warning: "These methods are not recommended because when your page changes,
  Playwright may click on an element you did not intend."
- Stability ranking: "Testing by test ids is the most resilient way of testing
  as even if your text or role of the attribute changes, the test will still
  pass."

(Apple's `XCUIElementQuery.element(boundBy:)` is the XCTest analogue of
`nth()`; its documentation page could not be fetched from a primary source
during this research — the developer.apple.com page is script-rendered and its
data endpoint returned 404 — so it is mentioned but not cited.)

### 4.4 Agent-facing guidance on identifiers

Source: Anthropic, "Writing tools for agents" (link in §3.2): "Agents also
tend to grapple with natural language names, terms, or identifiers significantly
more successfully than they do with cryptic identifiers", and resolving
"arbitrary alphanumeric UUIDs to more semantically meaningful and interpretable
language … significantly improves Claude's precision in retrieval tasks by
reducing hallucinations." The same page keeps "technical identifiers" available
in a `detailed` response format "for downstream tool calls".

### 4.5 How this maps onto the domain

Facts only; the domain already has a natural structural path and a known
non-uniqueness case:

- `CONTEXT.md` defines Block → Week (1–4) → Session (Day 1–N, "N … 2–6") →
  Exercise → Prescription Line → Set, so a path such as
  `week/2/day/3/exercise/1/set/2` is index-addressable at every level
  (`CONTEXT.md:9-25`).
- Exercise names are explicitly non-unique across Sessions and even within the
  Movement notion ("several spellings of the same name", `CONTEXT.md:21`;
  Movement, `CONTEXT.md:65`), so a name-based address would need Playwright-
  style strictness or Git-style tie-break rules; an index-based address does not.
- Sets are prescribed per Prescription Line and a Line "may represent multiple
  Sets" (`CONTEXT.md:25`), so "set 2 of exercise 1" is unambiguous only if the
  numbering rule (flat across Lines vs per-Line) is stated.
- The Sheet is the source of truth (ADR-0001), so a Kubernetes-style opaque
  `uid` would have to be minted client-side and would not survive a re-parse
  unless derived from Sheet coordinates — the closest existing stable handle is
  the cell target that ADR-0003 already computes.

---

## 5. Snapshot / golden-transcript testing of CLI output

### 5.1 swift-snapshot-testing text strategies

Source: `Sources/SnapshotTesting/Snapshotting/String.swift` (pointfreeco,
`main`),
<https://github.com/pointfreeco/swift-snapshot-testing/blob/main/Sources/SnapshotTesting/Snapshotting/String.swift>:

```swift
/// A snapshot strategy for comparing strings based on equality.
public static let lines = Snapshotting(pathExtension: "txt", diffing: .lines)
```

and "A line-diffing strategy for UTF-8 text." (`Diffing.lines`). So a CLI's
stdout can be asserted with `assertSnapshot(of: output, as: .lines)` and the
reference lives as a `.txt` file.

Source: README, <https://github.com/pointfreeco/swift-snapshot-testing>:
`.dump` "produces mirror-based output"; `.json` is for `Codable` values
(`assertSnapshot(of: user, as: .json)`) — usable directly on a decoded CLI
response type, which also pins the JSON contract.

Source: `Sources/SnapshotTesting/AssertSnapshot.swift` (same repo):
"snapshots will be saved in a directory with the same name as the test file,
and that directory will sit inside a directory `__Snapshots__` that sits next
to your test file"; `named` is "An optional description of the snapshot"; the
missing-reference failure reads "No reference was found on disk. New snapshot
was not recorded because recording is disabled". Record mode can be forced from
the environment: the file reads
`ProcessInfo.processInfo.environment["SNAPSHOT_TESTING_RECORD"]` into
`SnapshotTestingConfiguration.Record`.

Source: `Sources/SnapshotTesting/SnapshotTestingConfiguration.swift` (same
repo), record modes: `.all` "Records all snapshots to disk, no matter what.";
`.failed` "Records snapshots for assertions that fail."; `.missing` "Records
only the snapshots that are missing from disk."; `.never` "Does not record any
snapshots. If a snapshot is missing a test failure will be raised. This option
is appropriate when running tests on CI so that re-tries of tests do not
surprisingly pass after snapshots are unexpectedly generated."

Source: `Documentation.docc/Articles/IntegratingWithTestFrameworks.md` (same
repo): "In a Swift Testing context you can apply the `Testing/Trait/snapshots`
trait to either a single test or an entire suite", e.g.
`@Suite(.snapshots(record: .failed, diffTool: .ksdiff))`.

### 5.2 Inline transcripts

Source: `Sources/InlineSnapshotTesting/AssertInlineSnapshot.swift` (same repo).
`assertInlineSnapshot` "Asserts that a given value matches an inline string
snapshot." The `matches` closure is "An optional closure that returns a
previously generated snapshot. When omitted, the library will automatically
write a snapshot into your test file at the call sight of the assertion." The
rewrite happens at process exit via an `atexit` handler (`writeInlineSnapshots()`
→ `SnapshotRewriter`). This is the mechanism for keeping a short golden
transcript next to the command that produced it.

### 5.3 Swift Testing facts that bear on determinism

Source: swift-testing README, <https://github.com/swiftlang/swift-testing>:
"All tests integrate seamlessly with Swift Concurrency and run in parallel by
default." "Parameterized tests help you run the same test over a sequence of
values so you can write less code." "Swift Testing is included with the Swift
6 toolchain and Xcode 16."

Source: `Sources/Testing/Testing.docc/Parallelization.md` (same repo): "By
default, tests run in parallel with respect to each other." "Parallelization
can be disabled on a per-function or per-suite basis using the
`Trait/serialized` trait". Golden tests that share an on-disk state directory
or a process-wide environment variable (e.g. `SNAPSHOT_TESTING_RECORD`) are
therefore subject to parallel interference unless serialized or given isolated
temp directories.

### 5.4 What this repo already has

- `Tests/Visual/SessionViewVisualTests.swift:1-10` imports `SnapshotTesting`
  and `Testing` and declares `@Suite(.snapshots(record: .never))` — the CI-safe
  mode from §5.1 is already the house pattern.
- The dependency is wired through `WorkoutTracker.xcodeproj/project.pbxproj:1304`
  (`https://github.com/pointfreeco/swift-snapshot-testing`), not
  `Package.swift`, so a `swift test`-only CLI test target would need the
  dependency added to the package manifest as well.
- `Tests/Support/WorkoutScenarios.swift` and `LocalWorkbookSheetsClient.swift`
  are the existing headless scenario boot and offline Sheet stand-in (map #519
  "Evidence base"), i.e. the fixture source a golden CLI test would run against.

---

## Options for the grilling tickets (not decisions)

1. **Machine mode as a named, versioned contract.** Options seen: a `--json`
   flag with mandatory field selection and an "unknown field lists the valid
   set" error (gh); a `--porcelain=vN` version parameter with "ignore unknown
   headers" as the parser rule (git); or an in-band `schema`/`capabilities`
   field on the first record (Kubernetes `apiVersion`, Claude `system/init`).
   Any of these is stronger than none; the sources do not favour one.
2. **Stream vs document.** Options: one JSON document per invocation (gh,
   kubectl, docker) or NDJSON with a `type`/`reason` discriminator and a
   guaranteed terminal record (`build-finished`, `result`, `turn.completed`).
   A stream only earns its cost if commands are long-running or multi-step
   (e.g. a sync or a scripted Session); the harness reads back ~30k chars, so
   either way output needs pagination/`--fields` from day one.
3. **Where errors go.** Options: exit code + structured error object *on
   stdout* in the same schema (Kubernetes `Status`, Claude `result.is_error`),
   or exit code + diagnostics on stderr with stdout reserved for the result
   (Codex, rustc). The in-band `<object> missing` record from `git cat-file` is
   the model if a batch mode is chosen, so one bad address does not abort the
   script.
4. **Process model.** Options: one-shot with a scenario/state directory
   addressed by path or ID (`--resume <id>` / transcript path pattern); one-shot
   plus a `--batch` stdin command mode with "same order as read" output and
   `flush` semantics; a daemon only if a measured cold-start cost demands it,
   accepting the documented lock/idle/staleness costs and the harness's ~5 s
   post-result kill of background processes.
5. **Addressing.** Options: structural index paths mirroring the glossary
   (`week/2/day/3/exercise/1/set/2`), with the Set-numbering rule across
   Prescription Lines stated; names accepted only under strict resolution
   (error on >1 match, `--nth` opt-out) or under a published tie-break; and/or
   a derived stable handle (Sheet cell target per ADR-0003) exposed in a
   `detailed` output so agents can chain calls without re-resolving.
6. **Golden tests.** Options: `assertSnapshot(of: stdout, as: .lines)` per
   command with `record: .never` in CI (already the house pattern);
   `assertSnapshot(of: decoded, as: .json)` to pin the schema; inline snapshots
   for short transcripts; and `.serialized` or per-test temp directories when
   tests share state. Adding swift-snapshot-testing to `Package.swift` is a
   prerequisite for `swift test`-only coverage.
7. **Simulator relation.** Shopify's one documented shape is a single CLI with
   a "remote mode" that drives the running app "via commands" rather than the
   accessibility tree. The option here is whether the headless CLI's verb set
   is also the command set an in-app remote endpoint would accept, or whether
   the two stay separate (map #468's sighted loop unchanged).
