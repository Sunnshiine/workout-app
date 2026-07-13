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
| Trigger | push to `main` (path-filtered) + `workflow_dispatch` | `testflight` label on a PR (per-build) + `workflow_dispatch` with a PR number |
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

Applying the `testflight` label uploads the PR's **current head** once. Pushes
never upload — for another build, remove and re-apply the label. When
processing finishes, the workflow posts a receipt comment with the build
number.

**AGENT_PAT quirk**: a label applied by a workflow authenticated with the
plain `GITHUB_TOKEN` does **not** fire the workflow — GitHub suppresses
token-driven events. An agent that wants to ship a build must apply the label
using `AGENT_PAT`. (Same suppression the CI workflow documents for pushes.)

Fork PRs are skipped explicitly: they have no secrets, so they can never
upload.

## Pipeline shape

macOS job (40-min timeout): `xcodegen generate` → write `Secrets.xcconfig`
from secrets → PlistBuddy stamping → import the Apple Distribution cert into
a throwaway keychain (see [Distribution certificate](#distribution-certificate))
→ `xcodebuild archive` with automatic signing (`-allowProvisioningUpdates` +
the ASC API key; no fastlane — profiles for all four bundle ids are managed
headlessly, signed with the imported cert) → `-exportArchive`
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
| `DIST_CERT_P12_BASE64` | the Apple Distribution certificate + private key (`.p12`), base64-encoded | archive jobs, both workflows | exported from the Mac that owns the cert's private key — see [Distribution certificate](#distribution-certificate) | Re-export and update whenever the cert is renewed/replaced (certs last ~1 year) |
| `DIST_CERT_PASSWORD` | the password chosen when exporting that `.p12` | same | chosen at export time | rotates with `DIST_CERT_P12_BASE64` |

## Distribution certificate

Both workflows sign with an **imported** Apple Distribution certificate
rather than letting cloud signing mint one. The account sits at Apple's
Distribution-certificate ceiling, so a fully-automatic run dies at archive
with *"Choose a certificate to revoke. Your account has reached the maximum
number of certificates"* — followed by "No profiles found" for every bundle
id, because without a cert no profile can be created. Reusing the existing
cert avoids revoking anything (revocation would also invalidate whatever
else was signed with it).

Mechanics: the archive job decodes `DIST_CERT_P12_BASE64` into a throwaway
keychain before `xcodebuild archive`. Automatic signing prefers a valid
identity already in the keychain and only creates a new certificate when
none is available, so `-allowProvisioningUpdates` is left to manage the four
App Store profiles — profiles have no ceiling and stay headless.

**Exporting the `.p12`** (on the Mac whose keychain holds the private key —
the cert is useless for CI without it):

1. Keychain Access → login keychain → **My Certificates** → find
   `Apple Distribution: <name> (K74Q6RKFBY)` **with a disclosure triangle**
   (the triangle means the private key is present). If no entry has one, the
   private key is lost on this machine — see the fallback below.
2. Right-click the certificate → *Export…* → format **.p12**, choose a
   password.
3. `base64 -i Certificates.p12 | pbcopy` → paste into the
   `DIST_CERT_P12_BASE64` repo secret; put the password in
   `DIST_CERT_PASSWORD`.

**Inventory**: the `ASC Signing Inventory` workflow
(`.github/workflows/asc-signing-inventory.yml`, `workflow_dispatch`) lists
the account's certificates and profiles (metadata only) via the ASC API —
use it to see what occupies the ceiling and which cert the exported `.p12`
must match (compare expiry dates).

**If the private key is lost**: reuse is impossible — a certificate's
private key exists only where its CSR was generated (plus any `.p12`
exports). The remaining path is revoking a Distribution cert in the
[developer portal](https://developer.apple.com/account/resources/certificates/list)
to free a slot, then either minting fresh via cloud signing (drop the import
step) or generating a new cert locally and exporting it as above. Revoking a
**distribution** cert does not break apps already on TestFlight/App Store;
it invalidates any not-yet-uploaded signed artifacts and other pipelines
using that cert.

## Version bumping

The stable marketing version lives in **one** place:
`project.yml` → `WorkoutTracker` target → `info.properties.CFBundleShortVersionString`.
Hand-bump it at real releases; the workflows copy it to the widget and own
`CFBundleVersion` (never bump that by hand — it is the run number).
