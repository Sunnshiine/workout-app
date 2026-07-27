# TestFlight distribution

How builds get from this repo into TestFlight. Designed on the
[TestFlight CI/CD Wayfinder map (#344)](https://github.com/Sunnshiine/workout-app/issues/344);
the load-bearing decisions are
[#348 (pipeline)](https://github.com/Sunnshiine/workout-app/issues/348),
[#347 (build identity)](https://github.com/Sunnshiine/workout-app/issues/347),
[#353 (dev flavor runs live-Sheet)](https://github.com/Sunnshiine/workout-app/issues/353), and
[#349 (provisioning record)](https://github.com/Sunnshiine/workout-app/issues/349).

## The two tracks

| | Stable | PR (dev flavor) |
|---|---|---|
| Workflow | `.github/workflows/testflight-stable.yml` | `.github/workflows/testflight-pr.yml` |
| Trigger | push to `main` (path-filtered) + `workflow_dispatch` | `testflight` label on a PR (per-build; auto-removed at run start) + `workflow_dispatch` with a PR number |
| Bundle ids | `com.sunnypatel.WorkoutTracker` (+ `.Widgets`) | `com.sunnypatel.WorkoutTracker.dev` (+ `.dev.Widgets`) via `BUNDLE_ID_SUFFIX=.dev` |
| App Store Connect record | "TFN Tracker" | "TFN Tracker Dev" |
| Home-screen name | WorkoutTracker | WT Dev (`APP_DISPLAY_NAME` override) |
| App icon | Sunbird, green (`AppIcon` set) | Sunbird, amber (`APPICON_NAME=AppIconDev` override) |
| Marketing version | hand-bumped in `project.yml` (app target `CFBundleShortVersionString`) | `0.<PR number>` |
| Build number | `github.run_number` | `github.run_number` |
| Google OAuth client | stable pair (`GID_*` secrets) | "WorkoutTracker Dev iOS" (`DEV_GID_*` secrets) |
| Data | the coach-managed Sheet | live Sheets API — point the picker at a **cloned** training log |

Both tracks: the widget carries the identical version pair as its app (Apple
requires the match), and `GitCommit` / `PRNumber` / `Branch` / `RunNumber` are
stamped into the app's `Info.plist` before archiving (`PRNumber` is empty on
stable builds).

App icons ship in two forms selected by the same `APPICON_NAME`: Icon
Composer glass documents (`WorkoutTracker/AppIcon.icon` /
`AppIconDev.icon`, iOS 26 renders true Liquid Glass; authored in
[#373](https://github.com/Sunnshiine/workout-app/issues/373)) and raster
`.appiconset` fallbacks — single-size 1024 with dark/tinted appearance
variants, rendered from the SVG sources in `docs/design/app-icon/` by
`scripts/generate-app-icons.sh` (design decided in
[#370](https://github.com/Sunnshiine/workout-app/issues/370), produced in
[#369](https://github.com/Sunnshiine/workout-app/issues/369)). Don't edit the
PNGs by hand — edit the SVGs and re-render.

## Label semantics (PR builds)

Applying the `testflight` label uploads the PR's **current head** once. The
label is a push button: the workflow removes it as soon as a run starts, so
for another build just apply the label again — no manual removal needed.
Applying it while a build is in flight cancels that build and starts over from
the new head. Pushes never upload. When processing finishes, the workflow
posts a receipt comment with the build number; a failed run posts a failure
comment with the run link instead.

`agent-review.yml` applies the label automatically (via `AGENT_PAT`) after a
successful review pass, right after marking the PR ready for review — so a PR
going ready comes with a device build. The hand-off is skipped when the diff
vs `main` cannot affect the binary (docs, markdown, `.github/`, `.claude/`,
`.sandcastle/` only — the same excludes `testflight-stable.yml` uses). The
feedback-fix flow (`agent-implement-pr.yml`) does **not** re-apply the label;
during review back-and-forth, apply it manually when you want a build.

**AGENT_PAT quirk**: a label applied by a workflow authenticated with the
plain `GITHUB_TOKEN` does **not** fire the workflow — GitHub suppresses
token-driven events. An agent that wants to ship a build must apply the label
using `AGENT_PAT`. (Same suppression the CI workflow documents for pushes.)

Fork PRs are skipped explicitly: they have no secrets, so they can never
upload.

## Pipeline shape

macOS job (40-min timeout): `xcodegen generate` → write `Secrets.xcconfig`
from secrets → PlistBuddy stamping → import the signing certs into a
throwaway keychain (see [Signing certificates](#signing-certificates)) →
`xcodebuild archive` with automatic signing (`-allowProvisioningUpdates` +
the ASC API key; no fastlane — profiles for all four bundle ids are managed
headlessly, signed with the imported identities) → `-exportArchive`
(`app-store-connect`, automatic signing,
`manageAppVersionAndBuildNumber: false`) → `.ipa` artifact.

Linux job: `apple-actions/upload-testflight-build@v5` (AppStoreAPI backend,
`wait-for-processing`) → receipt comment (PR track only). The split exists
because Apple's processing wait is unbounded and must not occupy one of the
five free-tier macOS slots.

Concurrency groups `testflight-stable` / `testflight-pr-<number>` cancel
in-progress runs — newest wins, stale archives stop.

**Fallback** (documented, not built): if cloud signing proves flaky on hosted
runners, fastlane `match` with a private cert-store repo is the researched
alternative — see the
[pipelines research](../research/2026-07-11-testflight-upload-pipelines.md).

## Secrets

All live in GitHub → repo **Settings → Secrets and variables → Actions**.
Names and locations only — never record values (public repo).

| Secret | Holds | Consumed by | Upstream source | Rotation |
|---|---|---|---|---|
| `ASC_KEY_ID` | ASC API key ID, role **Admin** — cloud signing must create the Apple Distribution cert at export, which App Manager keys cannot ("Cloud signing permission error") | archive + upload jobs, both workflows | App Store Connect → Users and Access → Integrations → Team Keys | Create a new team key (roles can't be edited on an existing key), update `ASC_KEY_ID` + `ASC_PRIVATE_KEY`, revoke the old key |
| `ASC_ISSUER_ID` | ASC issuer ID | same | same page | Fixed per team; changes only with the Apple account |
| `ASC_PRIVATE_KEY` | the key's `.p8` content, **raw multiline PEM** pasted as-is (incl. the BEGIN/END lines) | same | same (downloadable exactly once; Sunny keeps the file privately) | Rotates together with `ASC_KEY_ID` |
| `GID_CLIENT_ID` | stable app's Google OAuth iOS client ID | stable archive job (written into `Secrets.xcconfig`) | Google Cloud console → APIs & Services → Credentials | Create a new iOS client for `com.sunnypatel.WorkoutTracker`, update both `GID_*` secrets |
| `GID_REVERSED_CLIENT_ID` | its reversed form | same | derived from `GID_CLIENT_ID` | with `GID_CLIENT_ID` |
| `DEV_GID_CLIENT_ID` | "WorkoutTracker Dev iOS" client ID | PR archive job (written into `Secrets.xcconfig`) | same console, client for `com.sunnypatel.WorkoutTracker.dev` | as above, for the dev client |
| `DEV_GID_REVERSED_CLIENT_ID` | its reversed form | same | derived | with `DEV_GID_CLIENT_ID` |
| `AGENT_PAT` | pre-existing agent PAT (Sandcastle pipeline) | applying the `testflight` label from automation | pre-existing | unchanged by this pipeline |
| `DIST_CERT_P12_BASE64` | the Apple Distribution certificate + private key (`.p12`), base64-encoded | archive jobs, both workflows | exported from the Mac that generated the cert — see [Signing certificates](#signing-certificates) | Re-export and update when the cert is renewed/replaced (certs last ~1 year) |
| `DIST_CERT_PASSWORD` | the password chosen when exporting that `.p12` | same | chosen at export time | rotates with `DIST_CERT_P12_BASE64` |
| `DEV_CERT_P12_BASE64` | an Apple Development certificate + private key (`.p12`), base64-encoded — archives are dev-signed before export re-signs them | same | exported from a Mac whose keychain holds a dev cert's key | as above |
| `DEV_CERT_PASSWORD` | the password chosen when exporting that `.p12` | same | chosen at export time | rotates with `DEV_CERT_P12_BASE64` |

## Signing certificates

Both workflows sign with **imported** certificates rather than letting cloud
signing mint them.

**Why (July 2026 incident)**: `xcodebuild archive` with automatic signing
dev-signs the archive; Apple Distribution only comes into play at
`-exportArchive`. On an ephemeral runner the keychain is empty, so every
cloud-signing run minted a **new Apple Development certificate** via the ASC
API — whose private key died with the runner. After ~12 runs the account hit
Apple's certificate ceiling and archives started dying with *"Choose a
certificate to revoke. Your account has reached the maximum number of
certificates"*, followed by "No profiles found" for every bundle id (no
usable cert → no profile can be created). At that point the account held 12
orphaned `Created via API` Development certs, zero Distribution certs, and
zero profiles (the pipeline had never reached export). The `ASC Signing
Inventory` workflow (`.github/workflows/asc-signing-inventory.yml`) lists
the account's certs/profiles — metadata only — to verify this state; run it
via `workflow_dispatch` (or, pre-merge, by pushing a change to the file).

Automatic signing only creates a certificate when the keychain has no valid
identity, so the archive job decodes both `.p12` secrets into a throwaway
keychain first: the Apple Development identity signs the archive, the Apple
Distribution identity signs the export, and `-allowProvisioningUpdates`
manages the four profiles — profiles have no ceiling and stay headless.

**Producing the two `.p12` secrets** (each cert is only usable in CI
together with its private key, which lives in the keychain of the Mac that
created it):

1. *Apple Development*: already exists — Keychain Access → login keychain →
   **My Certificates** → `Apple Development: <name>` with a disclosure
   triangle (= private key present).
2. *Apple Distribution*: create one (the distribution slots are free):
   Xcode → Settings → Accounts → *Manage Certificates…* → **+** →
   *Apple Distribution*. It lands in the login keychain with its key.
3. Export each: right-click → *Export…* → format **.p12**, choose a
   password. Then `base64 -i <file>.p12 | pbcopy` → paste into
   `DIST_CERT_P12_BASE64` / `DEV_CERT_P12_BASE64`; passwords go in
   `DIST_CERT_PASSWORD` / `DEV_CERT_PASSWORD`.

**Optional cleanup**: the 12 `Created via API` Development certs are
unusable junk (their keys are unrecoverable) and can be revoked in the
[developer portal](https://developer.apple.com/account/resources/certificates/list)
to free the ceiling — revoking them breaks nothing since nothing was ever
signed and shipped with them, and no profiles reference them. Keep the
`Sunny Patel` Development certs: their keys live on real Macs. This cleanup
is not required once the imported identities are in place (nothing mints
certs anymore), but it leaves headroom if the import step is ever bypassed.

## Version bumping

The stable marketing version lives in **one** place:
`project.yml` → `WorkoutTracker` target → `info.properties.CFBundleShortVersionString`.
Hand-bump it at real releases; the workflows copy it to the widget and own
`CFBundleVersion` (never bump that by hand — it is the run number).
