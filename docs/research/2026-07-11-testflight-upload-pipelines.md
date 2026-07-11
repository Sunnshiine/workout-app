# TestFlight upload pipelines from GitHub Actions (research, ticket #345)

Date: 2026-07-11 · Status: research notes only — pipeline and build-identity decisions are separate tickets.

Repo facts verified locally: CI runs on `macos-26` with `CODE_SIGNING_ALLOWED=NO` and nothing signed
(`.github/workflows/ci.yml`); the Xcode project is XcodeGen-generated (`project.yml`) with team
`K74Q6RKFBY` and two bundle ids — `com.sunnypatel.WorkoutTracker` (app) and
`com.sunnypatel.WorkoutTracker.Widgets` (app-extension) — so App Store signing needs **two**
provisioning profiles; `Secrets.xcconfig` is git-ignored and CI compile-checks with the template.

## Short answer / recommendation

For a solo-owner repo with no existing signing infrastructure, the least-moving-parts pipeline is:

1. **Auth**: one App Store Connect **team API key** (`.p8` + key ID + issuer ID) stored as three
   GitHub Actions secrets. It serves both signing and upload; no Apple ID password, no 2FA, no
   cert-store repo.
2. **Signing**: `xcodebuild archive` **cloud signing** — `-allowProvisioningUpdates` plus
   `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`. With automatic signing
   it creates/repairs certificates and profiles for *all* targets, including the widget extension,
   headlessly on a fresh runner. Fallback if it proves flaky: fastlane `match` with a private
   cert-store repo (handles both bundle ids via `app_identifier` array).
3. **Upload**: `apple-actions/upload-testflight-build` (actively maintained, v5.2.1 May 2026,
   default backend is Apple's new Build Upload API) or fastlane `upload_to_testflight` if fastlane
   is adopted anyway. Both take the same API key and can set "What to Test" notes.
4. **Build identity**: `CURRENT_PROJECT_VERSION=${{ github.run_number }}` injected at the
   `xcodebuild` command line (iOS build numbers only need to increase *within* a marketing
   version); stamp PR/commit metadata into a custom Info.plist key and into the TestFlight
   release notes rather than into `CFBundleVersion`.
5. **Cost control**: macOS minutes burn included quota at **10×**; keep TestFlight uploads
   opt-in (`workflow_dispatch` + a PR label gate), not per-push.

---

## 1. Upload paths

### fastlane `upload_to_testflight` (alias `pilot`)

- Auth: App Store Connect API key is the documented preferred method ("uses official App Store
  Connect API", no 2FA, better performance than Apple ID); Apple ID + app-specific password
  (`FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`) is supported but only works together with
  `apple_id` (the numeric app ID) and `skip_waiting_for_build_processing`.
  Source: <https://docs.fastlane.tools/actions/upload_to_testflight/>
- Key parameters: `ipa`, `api_key_path` (JSON with key id/issuer/`.p8`), `changelog` ("What to
  Test" text), `localized_build_info` (per-locale What to Test), `skip_waiting_for_build_processing`,
  `distribute_external` (+ `groups`, requires waiting for processing).
  Source: <https://docs.fastlane.tools/actions/upload_to_testflight/>
- Cost: brings a Ruby/fastlane dependency into the workflow; in exchange it can also set
  changelogs, distribute to groups, and wait for processing in one step.

### `xcrun altool --upload-app`

- **Deprecation status (verified)**: only altool's *notarization* subcommands are deprecated —
  the Apple notary service stopped accepting uploads from altool/Xcode ≤13 on 2023-11-01, and
  `notarytool` is the replacement *for notarization only*. Apple's technote explicitly says the
  App Store subcommands (upload) "will continue working" and altool "is not deprecated for …
  upload[ing] apps to the App Store".
  Sources: <https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool>,
  <https://developer.apple.com/news/upcoming-requirements/?id=11012023a>,
  <https://developer.apple.com/forums/thread/709364>
- Apple's current App Store Connect help still lists altool as a supported upload method,
  alongside Xcode, Transporter, and the App Store Connect API.
  Source: <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- Auth: either an ASC API key (`--apiKey`/`--apiIssuer` with the `.p8` in `~/.appstoreconnect/private_keys`)
  or Apple ID + app-specific password. API key avoids 2FA entirely.

### App Store Connect API directly (Build Upload API)

- New since WWDC25: the ASC API now supports **build uploads natively** via
  `POST /v1/buildUploads` (create upload → upload file parts → complete), plus endpoints to list
  and read build uploads; webhooks give real-time delivery-status notifications. This removes the
  historical need for altool/Transporter/a Mac for the upload step itself.
  Sources: <https://developer.apple.com/documentation/appstoreconnectapi/build-uploads>,
  <https://developer.apple.com/documentation/appstoreconnectapi/post-v1-builduploads>,
  <https://developer.apple.com/videos/play/wwdc2025/324/>,
  <https://developer.apple.com/videos/play/wwdc2025/328/>
- Auth: ASC API JWT (key ID + issuer ID + `.p8`). The private key can be downloaded **only once**;
  team keys require Account Holder/Admin to create.
  Source: <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/>

### `xcodebuild -exportArchive` with upload destination

- `xcodebuild -exportArchive -exportOptionsPlist …` can itself distribute the archive (export or
  upload) when the plist's destination is set to upload; combined with the API-key auth flags this
  is a no-extra-tools upload path. Covered in Apple's WWDC23 session on streamlined distribution.
  Sources: <https://keith.github.io/xcode-man-pages/xcodebuild.1.html>,
  <https://developer.apple.com/videos/play/wwdc2023/10224/>

### `apple-actions/upload-testflight-build` (third-party action)

- Maintained: latest release **v5.2.1 (2026-05-14)**, 10 releases, ongoing development, ~265 stars.
- Inputs: `app-path` (.ipa/.pkg), `issuer-id`, `api-key-id`, `api-private-key`, `release-notes`
  (changelog), `uses-non-exempt-encryption`, `wait-for-processing` (default true), and `backend`
  with three options: **AppStoreAPI** (default; the new Build Upload API — runs on Linux *or*
  macOS), `altool`, and `transporter` (needs separate install on hosted runners).
- Auth: ASC API key only (no Apple ID path).
  Source: <https://github.com/apple-actions/upload-testflight-build>

### Per-path auth summary

| Path | ASC API key | Apple ID + app-specific password |
|---|---|---|
| fastlane pilot | yes (preferred) | yes (with `apple_id` + skip-processing caveats) |
| `xcrun altool --upload-app` | yes | yes |
| ASC Build Upload API | yes (only) | no |
| `xcodebuild -exportArchive` upload | yes (auth flags) | via Xcode-added account only (not CI-suitable) |
| apple-actions/upload-testflight-build | yes (only) | no |

## 2. Code signing in CI

### fastlane match

- Stores encrypted certs/profiles in a private **git repo, Google Cloud Storage, or Amazon S3**;
  decryption via `MATCH_PASSWORD`. CI usage is `readonly: true` (fetch, never mutate), installs
  certs into a temporary keychain and profiles into
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles`. Can authenticate to Apple with an
  ASC API key (no Apple ID).
- **Multiple bundle ids**: `app_identifier` accepts an array/comma-separated list (e.g. app +
  extension); match then creates and syncs a profile per identifier, including app extensions —
  so `["com.sunnypatel.WorkoutTracker", "com.sunnypatel.WorkoutTracker.Widgets"]` yields both
  App Store profiles under one shared distribution cert.
- Cert types: `appstore`, `development`, `adhoc`, `enterprise`, `developer_id`.
- Cost for a solo owner: one extra private repo (or bucket), one passphrase secret, plus fastlane
  itself in the workflow. Requires manual signing settings (profile-per-target) in the project.
  Source: <https://docs.fastlane.tools/actions/match/>

### Manual .p12 + profiles as GitHub secrets

- `apple-actions/import-codesign-certs` (latest **v7.0.0, 2026-04-21**, maintained) imports a
  base64-encoded `.p12` into a fresh temporary keychain (`p12-file-base64`, `p12-password`,
  optional keychain name/password, `create-keychain`). It handles **certificates only — not
  provisioning profiles**; multiple certs can ride in one .p12.
  Source: <https://github.com/apple-actions/import-codesign-certs>
- The **two** provisioning profiles (app + widget extension) must each be exported from the
  developer portal, base64'd into secrets, and written to
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles/` (or the legacy
  `~/Library/MobileDevice/Provisioning Profiles/`) in a workflow step, then referenced per target
  (manual signing) and in `ExportOptions.plist`. Every profile renewal (annual cert expiry, App ID
  capability change) is a manual secret-rotation chore across both profiles.

### xcodebuild cloud signing (`-allowProvisioningUpdates` + API key)

- Documented flags (xcodebuild man page): `-allowProvisioningUpdates` lets xcodebuild talk to the
  Apple Developer website — "For automatically signed targets, xcodebuild will create and update
  profiles, app IDs, and certificates. For manually signed targets, xcodebuild will download
  missing or updated provisioning profiles." Without an API key it "requires a developer account
  to have been added in Xcode's Accounts preference pane"; the headless alternative is
  `-authenticationKeyPath` (ASC `.p8`), which "if specified, xcodebuild will authenticate with the
  Apple Developer website using this credential", together with `-authenticationKeyID` and
  `-authenticationKeyIssuerID`.
  Source: <https://keith.github.io/xcode-man-pages/xcodebuild.1.html>
- **Headless CI**: with the key triplet no logged-in Xcode account or keychain cert import is
  needed; Apple's streamlined-distribution WWDC23 session and developer-forum guidance describe
  exactly this keyID/keyFile/issuerID triplet for CI. Because it acts per *automatically signed
  target*, it creates/repairs profiles for the app **and** the widget extension in one archive.
  Sources: <https://developer.apple.com/videos/play/wwdc2023/10224/>,
  <https://developer.apple.com/forums/thread/756119>
- Caveats:
  - Certificates created this way are Apple-managed "cloud signing" certs tied to the API key's
    team; the key needs a role allowed to manage certificates/profiles (team keys are created by
    Account Holder/Admin). Source: <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/>
  - Reported intermittent cloud-signing failures on CI with newer Xcode versions exist (e.g.
    Xcode 16 thread) — worth a retry step. Source: <https://developer.apple.com/forums/thread/766722>
  - **XcodeGen**: nothing cloud-signing-specific, but the generated project must opt into
    automatic signing for Release. `project.yml` currently pins `CODE_SIGN_IDENTITY: iPhone
    Developer` on both targets and CI never regenerates/sign-builds; a release workflow must run
    `xcodegen` (or commit the project) and set `CODE_SIGN_STYLE: Automatic` +
    `DEVELOPMENT_TEAM` on **both** targets so `-allowProvisioningUpdates` can manage them.

### ExportOptions.plist for App Store distribution with an app extension

- `-exportArchive` requires `-archivePath`, `-exportOptionsPlist`, and `-exportPath`; the full key
  list is printed by `xcodebuild -help`. Source: <https://keith.github.io/xcode-man-pages/xcodebuild.1.html>
- `method` is now **`app-store-connect`** — the old `app-store` name is deprecated (as are
  `ad-hoc` → `release-testing`, `development` → `debugging`).
  Source: <https://developer.apple.com/forums/thread/773749>
- With **automatic/cloud signing**, `signingStyle=automatic` + `teamID` suffice; xcodebuild
  resolves both targets' profiles itself. With **manual signing**, the `provisioningProfiles`
  dictionary must map *every* bundle id to a profile name/UUID — i.e. two entries here:
  `com.sunnypatel.WorkoutTracker` and `com.sunnypatel.WorkoutTracker.Widgets` (key list per
  `xcodebuild -help`). `destination` chooses `export` (produce .ipa for a separate upload step)
  vs `upload` (xcodebuild uploads directly). `manageAppVersionAndBuildNumber` (default true) lets
  Xcode rewrite the build number at export time — set it to `false` if CI owns `CFBundleVersion`.

## 3. Build identification levers

- **Apple's rules (TN2420)**: `CFBundleShortVersionString` (marketing version) and
  `CFBundleVersion` (build string) must be period-separated numbers, 1–3 components, begin/end
  with a digit, ≤18 characters. Version numbers must be unique and increasing. For **iOS**, build
  numbers must be unique and increasing *within* a version's release train but **may be reused
  across different versions** (unlike macOS, where they must increase globally).
  Source: <https://developer.apple.com/library/archive/technotes/tn2420/_index.html>
- **Duplicate upload behavior**: uploading the same `CFBundleVersion` again for the same version
  is rejected at delivery validation — historically `ERROR ITMS-4238 "Redundant Binary Upload"`,
  and "The bundle version, NNN, must be a higher than the previously uploaded version" when it is
  not higher. Nothing is overwritten; the upload simply fails.
  Sources: <https://developer.apple.com/forums/thread/5860>, <https://developer.apple.com/forums/thread/693838>
- ASC uses bundle ID + version to attach the build to the app/version record, and "the build
  string is used to uniquely identify the build throughout the system."
  Source: <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- **GitHub run number**: `github.run_number` "begins at 1 for the workflow's first run, and
  increments with each new run" (per-workflow, stable across re-runs — use `run_attempt` to
  disambiguate re-runs). A per-workflow monotonic counter is a natural `CFBundleVersion`.
  Source: <https://docs.github.com/en/actions/learn-github-actions/contexts>
  - Encoding PR numbers: with the 3-component/18-char limit, `CFBundleVersion` like
    `<run_number>` or `<pr>.<run_number>` fits the format; but since iOS build numbers must be
    *increasing within the version*, a plain workflow-scoped counter is safer than PR-derived
    components (PR numbers don't arrive in order). Put PR/commit info elsewhere (below).
- **Mechanisms to set the numbers**:
  - Build settings: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` feed
    `CFBundleShortVersionString`/`CFBundleVersion` (directly with generated Info.plists, or via
    `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` placeholders in a real Info.plist). Both
    are overridable per-invocation: `xcodebuild … CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`.
    Reference: <https://developer.apple.com/documentation/xcode/build-settings-reference>
  - `agvtool new-version -all N` / `new-marketing-version X.Y` rewrite the numbers across all
    targets (keeps app + widget in lockstep — Apple requires extension versions to match);
    requires `CURRENT_PROJECT_VERSION` set and Versioning System = Apple Generic.
    Source: <https://developer.apple.com/library/archive/qa/qa1827/_index.html>
  - `INFOPLIST_KEY_*` build settings inject Info.plist keys at build time (generated-plist
    workflow), and `/usr/libexec/PlistBuddy -c "Set :Key value"` can stamp arbitrary keys (e.g.
    `GitCommit`, `PRNumber`) into a checked-in Info.plist before archiving. For this repo,
    XcodeGen's `info.properties` block is another injection point, but a pre-archive PlistBuddy
    step avoids coupling metadata to project generation.
    Reference: <https://developer.apple.com/documentation/xcode/build-settings-reference>
- **"What to Test" automation**:
  - fastlane: `changelog:` (single locale) or `localized_build_info:` on `upload_to_testflight`.
    Source: <https://docs.fastlane.tools/actions/upload_to_testflight/>
  - ASC API: `betaBuildLocalizations` resource — `POST /v1/betaBuildLocalizations` creates and
    `PATCH /v1/betaBuildLocalizations/{id}` modifies the localized What to Test text for a build.
    Sources: <https://developer.apple.com/documentation/appstoreconnectapi/beta-build-localizations>,
    <https://developer.apple.com/documentation/appstoreconnectapi/post-v1-betabuildlocalizations>,
    <https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-betabuildlocalizations-_id_>
  - `apple-actions/upload-testflight-build`: `release-notes` input.
    Source: <https://github.com/apple-actions/upload-testflight-build>

## 4. Practical constraints

- **Runner cost**: GitHub-hosted macOS jobs "consume minutes at … 10 times the rate that jobs on
  Linux runners consume" against included quota; pay-as-you-go rates are $0.062/min for macOS
  3-/4-core (M1/Intel) vs $0.006/min Linux 2-core (~10.3×). Included minutes: Free 2,000 /
  Pro 3,000 / Team 3,000 per month (standard runners; larger runners never use included minutes).
  Sources: <https://docs.github.com/en/billing/concepts/product-billing/github-actions>,
  <https://docs.github.com/en/billing/reference/actions-minute-multipliers>,
  <https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions>
- **Wall clock (estimate, not documented)**: this repo's existing unsigned compile-check job runs
  inside a 30-min timeout; a signed Release archive + export + upload for an app this size is
  typically in the ~15–25 min range on standard macOS runners — i.e. roughly 150–250
  Linux-equivalent minutes per upload. Treat as an estimate to be measured, not a cited fact.
- **Processing latency**: Apple documents no SLA — only that "the build needs to be processed in
  Apple's system before it appears in App Store Connect. You'll receive an email when this
  process is complete." Plan for minutes-to-hours; `wait-for-processing`/fastlane waiting steps
  burn paid macOS minutes while polling (apple-actions' AppStoreAPI backend can run the wait on a
  cheap Linux job instead).
  Source: <https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/>
- **TestFlight limits (verified)**: up to **100 internal testers** (team members with Account
  Holder/Admin/App Manager/Developer/Marketing roles), up to **10,000 external testers**, up to
  **100 builds** shared at once, testers on up to 30 devices; builds **expire 90 days** after
  upload (each new build gets its own 90-day window).
  Sources: <https://developer.apple.com/testflight/>,
  <https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/>
- **Duplicate `CFBundleVersion`**: second upload of the same version+build is rejected
  (Redundant Binary Upload / "must be higher"); see §3 sources.

## 5. Recommendation for this repo

Solo owner, no signing in CI today, XcodeGen project, two bundle ids, macOS at 10×:

1. **One secret set**: an ASC team API key (Admin-created) as `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_PRIVATE_KEY` (base64 `.p8`). Reused for signing *and* upload; no cert-store repo, no
   .p12 exports, no app-specific password.
2. **Cloud signing over match or manual .p12**: `xcodebuild archive` with
   `-allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`
   and automatic signing creates/repairs certs and *both* profiles (app + widget extension)
   headlessly — the extension's second profile is exactly the chore the other two approaches make
   manual (import-codesign-certs doesn't handle profiles at all; match needs the two-identifier
   array plus a storage repo). Prerequisite change: Release signing settings in `project.yml`
   (`CODE_SIGN_STYLE: Automatic`, keep `DEVELOPMENT_TEAM`, drop the pinned `CODE_SIGN_IDENTITY`
   for Release) and run `xcodegen` in the workflow. Keep fastlane match as the documented fallback
   if cloud signing is flaky on hosted runners.
3. **Export + upload**: `-exportArchive` with `method: app-store-connect`,
   `signingStyle: automatic`, `manageAppVersionAndBuildNumber: false`, `destination: export`;
   then `apple-actions/upload-testflight-build@v5` (maintained, ASC-API backend, same key,
   `release-notes` for What to Test). This avoids adopting fastlane/Ruby for a solo repo; if
   richer TestFlight automation is wanted later (groups, localized notes), fastlane pilot is the
   upgrade path.
4. **Build identity**: `CURRENT_PROJECT_VERSION=${{ github.run_number }}` of the release workflow
   (monotonic per workflow, valid to reuse across marketing versions on iOS); stamp
   PR number/commit SHA via PlistBuddy into custom Info.plist keys and into `release-notes`,
   not into `CFBundleVersion`.
5. **Keep it opt-in and cheap**: trigger via `workflow_dispatch` plus an explicit PR label (e.g.
   `testflight`), never on every PR push; single job, 30-min timeout, and let any
   wait-for-processing/notes step run on a Linux job. At ~10× billing, one upload ≈ 150–250
   Linux-minute-equivalents — affordable weekly, ruinous per-push.
