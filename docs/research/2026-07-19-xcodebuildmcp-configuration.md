# XcodeBuildMCP configuration for local + CI (sandcastle) use

- **Date:** 2026-07-19
- **Ticket:** #480 (research), feeds #472 (apply config)
- **Question:** What is the verified way to configure XcodeBuildMCP for this repo so it
  works both locally and inside a non-interactive Claude Code run on a GitHub Actions
  macOS runner (the sandcastle implement loop)?

Claims are labeled **[documented]** (stated in official docs/source), **[maintainer intent]**
(inferred from upstream code/changelog rather than a doc page), or **[open]** (docs do not
answer; becomes the spike in #472).

---

## 1. `.mcp.json` at repo root

**Package name and command** — [documented] The npm package is plain `xcodebuildmcp`
(NOT under the `@getsentry` scope, despite the repo living at `getsentry/XcodeBuildMCP`).
The official drop-in config for every MCP client is:

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    }
  }
}
```

Source: [xcodebuildmcp.com/docs/clients](https://xcodebuildmcp.com/docs/clients), which also
gives the Claude Code one-liner
`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`.

- [documented] The server subcommand is `mcp` — the binary is a combined CLI + MCP server;
  `xcodebuildmcp mcp` "speaks Model Context Protocol over stdio"
  ([docs](https://xcodebuildmcp.com/docs)).
- [documented] Homebrew install (`brew install getsentry/xcodebuildmcp/xcodebuildmcp`) is the
  promoted alternative and removes the Node.js requirement; npx requires Node 18+
  ([README](https://github.com/getsentry/XcodeBuildMCP)).
- [documented] Requirements: macOS 14.5+, Xcode 16.x+ ([README](https://github.com/getsentry/XcodeBuildMCP)).
- **Version pinning** — [maintainer intent] Upstream docs consistently use `@latest`; no doc
  page discusses pinning. For CI reproducibility, pinning a release (latest is **v2.6.2** as
  of 2026-07-19, per [GitHub releases](https://github.com/getsentry/XcodeBuildMCP/releases))
  in the CI invocation is our own best practice, not an upstream recommendation. A reasonable
  split: `@latest` in the shared `.mcp.json` for local dev, exact pin in the CI `--mcp-config`
  (see §6). Trade-off: a shared `.mcp.json` used by both must choose one.
- [documented] Claude Code expands `${VAR}` / `${VAR:-default}` in `.mcp.json` `command`,
  `args`, `env`, `url`, and `headers`
  ([MCP docs, "Environment variable expansion in .mcp.json"](https://code.claude.com/docs/en/mcp)).
- [documented] XcodeBuildMCP also reads a project-local YAML config,
  `<workspace-root>/.xcodebuildmcp/config.yaml` (`schemaVersion: 1`), with keys such as
  `enabledWorkflows` (default `["simulator"]`), `sessionDefaults`, `sentryDisabled`.
  Precedence: session runtime (`session_set_defaults` tool calls) > config file > env vars
  ([xcodebuildmcp.com/docs/configuration](https://xcodebuildmcp.com/docs/configuration)).
  For this repo the YAML file is the better home for session defaults (versioned, shared)
  with env vars as the CI override layer.

## 2. Non-interactive approval of project `.mcp.json` servers

Settings reference: [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings).

- [documented] `enableAllProjectMcpServers` (boolean): "Automatically approve all MCP servers
  defined in project `.mcp.json` files without prompting."
- [documented] `enabledMcpjsonServers` (array of server names): allowlist of specific
  `.mcp.json` servers, e.g. `["XcodeBuildMCP", "context7"]`. `disabledMcpjsonServers` is the
  denylist.
- [documented] All three are valid in user (`~/.claude/settings.json`), project
  (`.claude/settings.json`, checked in), and local (`.claude/settings.local.json`,
  gitignored) scope.

**Critical caveat for CI** — [documented] As of Claude Code v2.1.196, in an **untrusted
folder** these keys are honored only from settings files that are *not* checked into the
repository: "A cloned repository can't approve its own servers: `enableAllProjectMcpServers`
or `enabledMcpjsonServers` committed to the project's `.claude/settings.json` is ignored in
an untrusted folder, and the server stays at `⏸ Pending approval`"
([MCP docs](https://code.claude.com/docs/en/mcp)). Trust is granted by running `claude`
interactively and accepting the workspace-trust dialog — which never happens on a fresh CI
checkout.

- [documented] The escape hatch for CI: `--mcp-config <file-or-json>` loads servers
  explicitly, and `--strict-mcp-config` restricts the session to only those servers
  ([CLI reference](https://code.claude.com/docs/en/cli-reference)). Servers passed via
  `--mcp-config` sit outside the project-approval flow (the MCP docs treat them as
  explicitly provisioned, e.g. "Servers passed explicitly via `--mcp-config` are
  unaffected" by connector-disable settings).
- [open] Whether `--dangerously-skip-permissions` (which sandcastle's `claudeCode` agent
  passes — see §6) also bypasses the project-`.mcp.json` approval/trust gate in `-p` mode is
  not documented anywhere I could find. The spike in #472 should verify empirically; until
  then, `--mcp-config .mcp.json` in CI is the only fully documented path.

**Permission rules for the tools** — [documented] MCP permission rule syntax
([permissions docs](https://code.claude.com/docs/en/permissions)):

- `mcp__XcodeBuildMCP` — any tool from that server;
- `mcp__XcodeBuildMCP__*` — wildcard form, same effect;
- `mcp__XcodeBuildMCP__<tool>` — a single tool.

Allow-rule globs are only valid after a literal `mcp__<server>__` prefix ("The server
segment must be glob-free"); a bare `mcp__*` allow rule "is skipped with a warning". `mcp__*`
*is* valid in deny/ask rules. Note the server segment must match the `.mcp.json` key exactly
(case-sensitive), so the key spelling in `.mcp.json` and the permission rules must agree.

Under sandcastle's `--dangerously-skip-permissions` (= `bypassPermissions`) these allow rules
are moot for CI, but they make local interactive sessions frictionless.

## 3. `XCODEBUILDMCP_*` environment variables

Source: [xcodebuildmcp.com/docs/env-vars](https://xcodebuildmcp.com/docs/env-vars). The page
lists names in two tables (general settings; session-default bootstrap) with minimal prose.

**Session-default bootstrap** (seed the session-defaults layer at server startup; overridable
at runtime via `session_set_defaults` and by `.xcodebuildmcp/config.yaml`, per the
[configuration precedence](https://xcodebuildmcp.com/docs/configuration)) — this is the
implementation of the ask in upstream issue
[#180](https://github.com/getsentry/XcodeBuildMCP/issues/180), though the shipped names drop
the `_DEFAULT_` infix the issue proposed:

| Variable | Meaning | Set in CI for this repo? |
|---|---|---|
| `XCODEBUILDMCP_PROJECT_PATH` | Default `.xcodeproj` path | Yes — `WorkoutTracker.xcodeproj` (absolute path; worktree caveat in CLAUDE.md applies) |
| `XCODEBUILDMCP_WORKSPACE_PATH` | Default `.xcworkspace` path | No (repo uses a project, not a workspace) |
| `XCODEBUILDMCP_SCHEME` | Default scheme | Yes — `WorkoutTracker` |
| `XCODEBUILDMCP_CONFIGURATION` | Build configuration | Optional (`Debug`) |
| `XCODEBUILDMCP_SIMULATOR_NAME` | Default simulator by name | Yes — `iPhone 17 Pro` |
| `XCODEBUILDMCP_SIMULATOR_ID` | Default simulator by UDID | No (name is portable across runners) |
| `XCODEBUILDMCP_SIMULATOR_PLATFORM` / `XCODEBUILDMCP_PLATFORM` | Platform selection | Optional |
| `XCODEBUILDMCP_DEVICE_ID` | Physical device UDID | No |
| `XCODEBUILDMCP_USE_LATEST_OS`, `XCODEBUILDMCP_ARCH`, `XCODEBUILDMCP_DERIVED_DATA_PATH`, `XCODEBUILDMCP_PREFER_XCODEBUILD`, `XCODEBUILDMCP_SUPPRESS_WARNINGS`, `XCODEBUILDMCP_BUNDLE_ID` | Further build/run defaults | As needed |

**General settings** (selection):

- `XCODEBUILDMCP_ENABLED_WORKFLOWS` — comma-separated tool groups to expose (config-file
  default is `["simulator"]`).
- `XCODEBUILDMCP_DISABLE_SESSION_DEFAULTS` — turns the session-defaults layer off.
- `XCODEBUILDMCP_SENTRY_DISABLED` — telemetry opt-out. Recommend `true` in CI.
- `XCODEBUILDMCP_CWD` — server working directory (absolute; `~/` supported).
- `XCODEBUILDMCP_MCP_IDLE_TIMEOUT_MS` — idle self-shutdown, default `0` (disabled); useful in
  CI so an orphaned server exits.
- `XCODEBUILDMCP_DEBUG`, `XCODEBUILDMCP_SHOW_TEST_TIMING`, `XCODEBUILDMCP_DEBUGGER_BACKEND`,
  `XCODEBUILDMCP_DAP_REQUEST_TIMEOUT_MS`, `XCODEBUILDMCP_DAP_LOG_EVENTS`,
  `XCODEBUILDMCP_FILE_PATH_RENDER_STYLE` (`list`|`tree`),
  `XCODEBUILDMCP_UI_DEBUGGER_GUARD_MODE`, `XCODEBUILDMCP_AXE_PATH`,
  `XCODEBUILDMCP_DISABLE_XCODE_AUTO_SYNC`, template path/version vars — not needed for the
  sandcastle loop.

**`XCODEBUILDMCP_HEADLESS_LAUNCH`** — [maintainer intent] **not yet on the env-vars docs
page** (verified 2026-07-19), but shipped and described in the upstream
[CHANGELOG](https://github.com/getsentry/XcodeBuildMCP/blob/main/CHANGELOG.md): "an opt-in
`XCODEBUILDMCP_HEADLESS_LAUNCH` mode for automated runs that should not steal macOS focus:
macOS apps launch in the background, the Simulator window is not brought to the foreground
(the simulator runtime still boots), and keyboard-shortcut actions fail fast with a clear
foreground-focus requirement." Accepts `1` or `true` (case-insensitive), per
[`src/utils/focus-policy.ts`](https://github.com/getsentry/XcodeBuildMCP/blob/main/src/utils/focus-policy.ts),
whose header states it is "intended for snapshot/smoke tests and other CI-style runs".
**The CI job should set `XCODEBUILDMCP_HEADLESS_LAUNCH=1`.**

## 4. Headless constraints

- [documented in source] With `XCODEBUILDMCP_HEADLESS_LAUNCH=1`:
  - macOS app launches use `open -g` (background, no focus steal);
  - Simulator.app is never opened — the sim runtime is booted via `simctl boot` only, which
    the code comment says "maintains simulator availability for UI automation without
    surfacing a window" (`src/utils/focus-policy.ts`);
  - **keyboard-shortcut tools fail fast**: "Keyboard shortcuts require Simulator.app to be in
    the foreground, which is incompatible with XCODEBUILDMCP_HEADLESS_LAUNCH mode."
    (`src/mcp/tools/simulator-management/_keyboard_shortcut.ts`). This is the only tool
    class with an explicit headless fail-fast.
- [maintainer intent] Upstream runs its own snapshot/vitest suites with
  `XCODEBUILDMCP_HEADLESS_LAUNCH: '1'` (`vitest.snapshot.config.ts`), i.e. the headless path
  is exercised in their CI.
- [maintainer intent] Tap/swipe/screenshot UI automation goes through the bundled AXe/simctl
  path against the booted sim runtime, which the focus-policy comment says stays available
  headless. There is **no doc page** covering GUI-less macOS sessions specifically.
- [open] Whether AXe-based UI automation works on a GitHub Actions hosted macOS runner's
  session context is undocumented upstream. Mitigating context: GitHub-hosted macOS runners
  routinely run `xcodebuild test` with XCUITest/simulator UI, so a booted sim under
  `simctl` is normal there — but verifying tap/screenshot via XcodeBuildMCP on the runner is
  a #472 spike task.
- Practical consequence for this repo: build/test/launch/log tools and the UI-automation
  basics should work headless; avoid keyboard-shortcut tools in the sandcastle loop.

## 5. context7 MCP alongside

Source: [context7.com/docs/resources/all-clients](https://context7.com/docs/resources/all-clients)
and [upstash/context7 README](https://github.com/upstash/context7).

- **Remote (recommended, zero install):** endpoint `https://mcp.context7.com/mcp`, HTTP
  transport, API key via header:
  `claude mcp add --scope user --header "CONTEXT7_API_KEY: YOUR_API_KEY" --transport http context7 https://mcp.context7.com/mcp`.
  `.mcp.json` equivalent:

  ```json
  {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}" }
    }
  }
  ```

- **Local (stdio):** `npx -y @upstash/context7-mcp --api-key YOUR_API_KEY`.
- **API key:** free from [context7.com/dashboard](https://context7.com/dashboard); works
  without one at lower (unspecified) rate limits. The README now also promotes
  `npx ctx7 setup --claude` (OAuth + key generation + skill install) — an interactive flow,
  not suitable for CI.
- **Approval implications:** identical to XcodeBuildMCP — as a project-scope `.mcp.json`
  entry it needs the same approval treatment (§2): list it in `enabledMcpjsonServers`
  locally, and include it in the CI `--mcp-config` if the loop should have it. Claude Code's
  `${VAR}` expansion in `headers` keeps the API key out of git; if `CONTEXT7_API_KEY` is
  unset the config still loads with a warning ([MCP docs](https://code.claude.com/docs/en/mcp)).

## 6. Recommended config for this repo (PROPOSAL — to be applied by #472, files not created here)

The sandcastle loop runs `claude` via `@ai-hero/sandcastle`'s `claudeCode` agent with
`dangerouslySkipPermissions: true` (verified in the published package bundle), from
`.github/workflows/agent-implement.yml` → `.sandcastle/implement/implement.ts`. So CI does
not need permission allow rules — it needs the *servers connected* (§2 caveat) and the
*session-default env vars set*.

**Proposed `.mcp.json` (repo root):**

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest", "mcp"]
    },
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}" }
    }
  }
}
```

**Proposed `.claude/settings.json` additions (checked in):**

```json
{
  "enabledMcpjsonServers": ["XcodeBuildMCP", "context7"],
  "permissions": {
    "allow": ["mcp__XcodeBuildMCP__*", "mcp__context7__*"]
  }
}
```

(`enabledMcpjsonServers` over `enableAllProjectMcpServers` — allowlist beats blanket
approval, and both are equally ignored in untrusted folders, so nothing is lost.)

**Proposed session defaults** — prefer the versioned YAML,
`.xcodebuildmcp/config.yaml`:

```yaml
schemaVersion: 1
sessionDefaults:
  projectPath: WorkoutTracker.xcodeproj
  scheme: WorkoutTracker
  simulatorName: iPhone 17 Pro
sentryDisabled: true
```

(Exact key names to be confirmed from `xcodebuildmcp setup` output in #472; env-var
equivalents `XCODEBUILDMCP_PROJECT_PATH` / `XCODEBUILDMCP_SCHEME` /
`XCODEBUILDMCP_SIMULATOR_NAME` are the fallback and the per-worktree override.)

**Proposed CI env (macOS runner job):**

```yaml
env:
  XCODEBUILDMCP_HEADLESS_LAUNCH: "1"
  XCODEBUILDMCP_SENTRY_DISABLED: "true"
  XCODEBUILDMCP_PROJECT_PATH: ${{ github.workspace }}/WorkoutTracker.xcodeproj
  XCODEBUILDMCP_SCHEME: WorkoutTracker
  XCODEBUILDMCP_SIMULATOR_NAME: iPhone 17 Pro
```

**Open questions → spike in #472:**

1. Does the sandcastle-invoked `claude` (with `--dangerously-skip-permissions`, fresh
   checkout, no trust dialog) actually connect project `.mcp.json` servers, given the
   v2.1.196 untrusted-folder rule? If not, sandcastle needs a way to pass
   `--mcp-config .mcp.json --strict-mcp-config` (check whether `@ai-hero/sandcastle`
   exposes extra CLI args), or the workflow must pre-trust the folder (undocumented).
2. Verify AXe tap/swipe/screenshot works headless on a GitHub-hosted macOS runner.
3. Confirm `.xcodebuildmcp/config.yaml` key names via `xcodebuildmcp setup`.
4. Pin vs `@latest` for CI: decide whether to pin `xcodebuildmcp@2.6.2` in the CI
   `--mcp-config` while the shared `.mcp.json` tracks `@latest`.
5. `XCODEBUILDMCP_HEADLESS_LAUNCH` is absent from the env-vars docs page — consider an
   upstream docs PR, and re-check semantics on upgrade.

## Sources

- https://xcodebuildmcp.com/docs — overview, Homebrew install, `mcp` subcommand
- https://xcodebuildmcp.com/docs/clients — Claude Code / generic `.mcp.json` snippet, `npx -y xcodebuildmcp@latest mcp`
- https://xcodebuildmcp.com/docs/configuration — `.xcodebuildmcp/config.yaml`, precedence layers
- https://xcodebuildmcp.com/docs/env-vars — `XCODEBUILDMCP_*` tables (general + session-default bootstrap)
- https://github.com/getsentry/XcodeBuildMCP — README (requirements, npx form)
- https://github.com/getsentry/XcodeBuildMCP/blob/main/CHANGELOG.md — `XCODEBUILDMCP_HEADLESS_LAUNCH` semantics
- https://github.com/getsentry/XcodeBuildMCP/blob/main/src/utils/focus-policy.ts — headless focus policy implementation
- https://github.com/getsentry/XcodeBuildMCP/blob/main/src/mcp/tools/simulator-management/_keyboard_shortcut.ts — headless fail-fast
- https://github.com/getsentry/XcodeBuildMCP/issues/180 — session-default env var bootstrap request
- https://github.com/getsentry/XcodeBuildMCP/releases — v2.6.2 latest
- https://code.claude.com/docs/en/settings — `enableAllProjectMcpServers`, `enabledMcpjsonServers`, settings file scopes
- https://code.claude.com/docs/en/mcp — project `.mcp.json`, approval + untrusted-folder rule (v2.1.196), `${VAR}` expansion, `MCP_TIMEOUT`, per-server `timeout`
- https://code.claude.com/docs/en/permissions — `mcp__server__*` rule syntax and glob constraints
- https://code.claude.com/docs/en/cli-reference — `--mcp-config`, `--strict-mcp-config`, `--dangerously-skip-permissions`
- https://code.claude.com/docs/en/headless — `claude -p`, `--bare`, MCP loading in CI
- https://context7.com/docs/resources/all-clients — Context7 Claude Code install (remote + local)
- https://github.com/upstash/context7 — Context7 README (endpoint, API key, `ctx7 setup`)
