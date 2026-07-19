# The xcode-27 runner image: label, default Xcode, iOS 27 simulator runtime, and the actool icon-crash

Wayfinder research ticket #477 · 2026-07-19 · Part of map #468. Unblocks the
bump ticket #478 and pins the runtime for re-baseline ticket #479 (ADR-0007).

Grounds four ground-facts about GitHub's `xcode-27` hosted runner image against
primary sources (the `actions/runner-images` image README, the GitHub Actions
changelog, and GitHub Docs) plus Apple's Icon Composer material for the actool
question. **This document records facts only; the workflow bump and the actool
deletion are separate tickets (#478).**

---

## Summary (answer-first)

- **Runner label:** use **`runs-on: xcode-27`** (larger variant `xcode-27-xlarge`).
  There is **no `macos-27` label** — GitHub changed the hosted-macOS naming
  scheme so images are now keyed to a **major Xcode version, not a macOS
  version**. The image is **public preview** (announced 2026-07-16) and
  **arm64-only** (no Intel variant). `macos-26` is GA and not yet deprecated.
- **Default Xcode:** the image ships **exactly one** Xcode — **Xcode 27.0 beta
  (build `27A5218g`)** — and it **is the default** (`/Applications/Xcode.app`
  symlink → `Xcode_27_beta_3.app`). `xcodebuild` resolves to Xcode 27 with no
  `xcode-select` / `DEVELOPER_DIR` needed. Underlying OS: **macOS 26.5.2 (25F84)**.
- **iOS simulator runtime:** **iOS 27.0 is preinstalled** out of the box (SDK
  `iphonesimulator27.0`). **No `xcodebuild -downloadPlatform iOS` step is
  required.** The exact runtime string to pin in ADR-0007 is **`iOS 27.0`**.
- **actool icon-crash:** the owner's mechanism is **plausible but not confirmed
  by primary sources**. The `.icon` (Icon Composer) format itself is a **Xcode
  26 / iOS 26** feature, so "iOS-27-only `.icon` attribute" is imprecise as
  stated — but the repo's `AppIconDev.icon` declares `"features": ["refractivity"]`,
  and **refraction is exactly what iOS 27 revamps** and what the updated Icon
  Composer (bundled with Xcode 27) adds new authoring for. A forward `.icon`
  schema attribute that Xcode 26.5's `actool` can't open on the thinned device
  compile but Xcode 27's `actool` can is a coherent explanation. **The definitive
  test is building the actual `AppIconDev.icon` on the `xcode-27` image — defer
  to #478.**

---

## 1. Runner label

**Question.** What exact `runs-on:` label selects the xcode-27 image — a
`macos-*` label, `macos-latest`, or a pinned tag? How does the "xcode-27"
README map to an Actions label? GA vs beta, and is `macos-26` deprecated?

**Sources.**
- [Xcode 27 runner image now in public preview — GitHub Changelog, 2026-07-16](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview/)
- [`actions/runner-images` — README (available images)](https://github.com/actions/runner-images/blob/main/README.md)
- [`actions/runner-images` — `images/macos/xcode-27-Readme.md`](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-Readme.md)
- [macos-26 is now generally available — GitHub Changelog, 2026-02-26](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)
- [GitHub-hosted runners reference — GitHub Docs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

**Findings.**
- The label is **`xcode-27`**, with a larger-runner variant **`xcode-27-xlarge`**.
  Per the changelog: the new model is that "each image is based on a **major
  Xcode version rather than the underlying operating system**, and we will
  support one major Xcode version per image." So this is **not** reached via a
  `macos-*` label at all — the `xcode-27-Readme.md` filename *is* the label
  stem, not a macOS number.
- **There is no `macos-27` label.** The newest macOS-numbered image is
  `macos-26` (arm64; `macos-26-intel` for x64). The xcode-27 image runs on
  **macOS 26.5.2 (25F84)** underneath but is selected by the Xcode-versioned
  label, not a macOS-27 label.
- **Status: public preview**, announced **2026-07-16** (three days before this
  research). **arm64-only** — the image is not offered on Intel runners.
- **`macos-26`** went **GA on 2026-02-26** and is **not deprecated**; the
  changelog announces no removal date for it. `macos-latest` is a separate
  moving alias and should not be used for a pinned CI (it does not track
  xcode-27).

**Recommendation for #478:** replace `runs-on: macos-26` with
`runs-on: xcode-27`. Because the image is **public preview**, treat it as
potentially unstable/version-drifting and keep `macos-26` reachable as a
fallback until GA is announced.

---

## 2. Default Xcode

**Question.** What Xcode ships, and is Xcode 27 the default `xcodebuild` or must
it be selected via `xcode-select` / `DEVELOPER_DIR`? List available Xcodes.

**Sources.**
- [`actions/runner-images` — `images/macos/xcode-27-Readme.md`](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-Readme.md)

**Findings.**
- The image ships **exactly one** Xcode: **Xcode 27.0 (beta), build `27A5218g`**,
  installed at `/Applications/Xcode_27_beta_3.app`.
- It is the **default** — symlinked to `/Applications/Xcode.app` — so
  `xcodebuild` invokes Xcode 27 with **no `xcode-select`/`DEVELOPER_DIR`
  override required**.
- Consequence for #478: this is a **single-Xcode image**. There is no Xcode 26
  fallback on the same image; jobs that must stay on Xcode 26 must stay on the
  `macos-26` label. Do not assume the multi-Xcode `/Applications/Xcode_XX.app`
  selection pattern that older `macos-*` images offered.

---

## 3. Simulator runtimes

**Question.** Which iOS simulator runtimes are preinstalled? Is an iOS 27.x
runtime present out of the box, or must it be installed via
`xcodebuild -downloadPlatform iOS`? Exact version string.

**Sources.**
- [`actions/runner-images` — `images/macos/xcode-27-Readme.md`](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-Readme.md)

**Findings.**
- **iOS 27.0 is preinstalled** (SDK identifier `iphonesimulator27.0`), with the
  iOS 27.0 device set including **iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max,
  iPhone 17e, iPhone Air**, plus iPad models (iPad A16, iPad Air 11"/13" M4,
  iPad mini A17 Pro, iPad Pro 11"/13" M5).
- **No runtime download is required** — `xcodebuild -downloadPlatform iOS` is
  **not** needed for iOS 27.0 on this image.
- **Exact runtime string to pin in ADR-0007 (#479): `iOS 27.0`.**
- The project's default simulator is **`iPhone 17 Pro`** (CLAUDE.md), which is in
  the preinstalled iOS 27.0 device set — so the existing destination string
  keeps working under the iOS 27.0 runtime.

> Open item: the README excerpt surfaced only the iOS 27.0 runtime. Whether an
> older iOS 26.x runtime is *also* present on the image was not confirmable from
> the fetched section; if a job needs to test against iOS 26.x specifically,
> verify on the live image before relying on it (defer to #478).

---

## 4. `actool` icon-crash

**Question.** Is it true that the `AppIconDev.icon` build failure under Xcode
26.5's `actool` stems from an iOS-27-only `.icon` attribute, so Xcode 27's
`actool` opens the bundle directly and the workaround in `testflight-pr.yml` /
`testflight-stable.yml` can be **deleted**?

**Sources.**
- Repo: `.github/workflows/testflight-pr.yml:96-103` (the workaround and its
  comment), and `WorkoutTracker/AppIconDev.icon/icon.json` (the `.icon` schema).
- [Icon Composer — Apple Developer](https://developer.apple.com/icon-composer/)
- [Creating your app icon using Icon Composer — Apple Developer Documentation](https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer)
- [iOS 27 Revamps App Icons With Sharper Liquid Glass Layers — MacRumors, 2026-06-16](https://www.macrumors.com/2026/06/16/ios-27-revamps-app-icons/)

**What the repo actually does.** The workflow comment (`testflight-pr.yml:96-101`)
records: "actool in the runner's Xcode (26.5) cannot open the repo's Icon
Composer documents during the thinned device compile ('Cannot Open
AppIconDev.icon' + nil-insert crash), though **simulator builds accept them**."
The workaround (`rm -rf WorkoutTracker/AppIcon.icon WorkoutTracker/AppIconDev.icon`)
deletes the `.icon` documents before `xcodegen`, so release archives ship the
raster `.appiconset` fallbacks.

**Assessment of the owner's claim.**
- **The "iOS-27-only `.icon` attribute" framing is imprecise.** Per Apple, the
  `.icon` (Icon Composer) format and its `actool` consumption were **introduced
  with Xcode 26 / iOS 26** for the Liquid Glass design system — the format is
  not new in 27. So "the failure is because `.icon` is an iOS-27 thing" is not
  correct as literally stated.
- **But the mechanism is plausible at the attribute level.** The repo's
  `AppIconDev.icon/icon.json` declares `"features": ["refractivity"]` and
  per-group `refractivity` blocks. **Refraction is precisely what iOS 27
  revamps** — MacRumors (2026-06-16) reports iOS 27 replaces the uniform iOS-26
  glass with per-layer refraction and that **Icon Composer was updated with new
  annotation features to add refraction effects**. That updated Icon Composer
  ships with Xcode 27. So a `.icon` authored with the newer, refraction-aware
  schema plausibly contains attributes that **Xcode 26.5's older `actool`
  cannot parse on the strict thinned/device compile path** (while the more
  lenient simulator compile tolerates them) — and Xcode 27's `actool`, matching
  the authoring tool, would open it directly.
- **Net:** the *conclusion* (Xcode 27's actool opens the bundle, workaround
  deletable) is **credible and consistent** with the refraction-attribute
  evidence; the *stated reason* ("iOS-27-only") should be corrected to "a
  forward Icon-Composer/refraction `.icon` attribute not supported by Xcode
  26.5's actool."

**Definitive check (defer to #478).** Primary GitHub/Apple sources cannot settle
a repo-internal build failure. The one authoritative test is to **build the
actual `WorkoutTracker/AppIconDev.icon` (and `AppIcon.icon`) through the thinned
device archive on the `xcode-27` image** with the `rm -rf` workaround removed.
If that archive succeeds, delete the workaround in both
`testflight-pr.yml` and `testflight-stable.yml`; if it still fails, keep it and
re-author the icon in the newer Icon Composer.

---

## Confidence

| # | Question | Confidence | Why |
|---|---|---|---|
| 1 | Runner label `xcode-27` | **High** | Direct from GitHub changelog + runner-images README; consistent across both. |
| 2 | Default Xcode 27.0 beta `27A5218g`, sole Xcode | **High** | Direct from the xcode-27 image README. |
| 3 | iOS 27.0 runtime preinstalled, no download | **High** | Direct from the xcode-27 image README (SDK `iphonesimulator27.0`). |
| 4 | actool workaround deletable | **Moderate** | Mechanism consistent with refraction evidence, but no primary source builds this repo's `.icon`; requires the #478 build check. |

## Open questions (for #478)

1. Confirm whether an iOS 26.x simulator runtime co-exists with iOS 27.0 on the
   image (only iOS 27.0 was surfaced here).
2. Build `AppIconDev.icon` / `AppIcon.icon` on `xcode-27` with the `rm -rf`
   workaround removed — pass/fail decides whether the workaround is deleted.
3. `xcode-27` is **public preview**; watch for the GA announcement and any
   `macos-26` deprecation date before removing the fallback path.
