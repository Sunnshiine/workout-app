# Tuning the glass icons in Icon Composer 2 — a first-timer's guide

The final step of
[#373](https://github.com/Sunnshiine/workout-app/issues/373): the layered
glass icons already exist and are fully wired into the build — you are **not**
creating an icon from scratch. You're opening two existing documents in Icon
Composer, nudging a handful of material sliders with live preview until the
glass looks right, and committing whatever Icon Composer saves. No Xcode work
remains.

The two documents:

| File | Flavor | Disc fill (light / dark) |
|---|---|---|
| `WorkoutTracker/AppIcon.icon` | stable | deep green `#0B7A45` / mint `#73FFB8` |
| `WorkoutTracker/AppIconDev.icon` | WT Dev | vivid amber `#D9820F` / warm amber `#FFC873` |

Each is a package (right-click → Show Package Contents) holding `icon.json`
plus one SVG layer asset — the sun disc with the Sunbird as a negative-space
cutout. Icon Composer reads and writes that same `icon.json`, so the GUI and
the hand-authored file are two views of one document.

## 1. Install Icon Composer 2 beta

- Download from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Icon%20Composer)
  (search "Icon Composer"). A free Apple developer account is enough; no paid
  membership needed.
- Requires macOS Tahoe 26.4 or later.
- Version 2 (beta since WWDC26) adds **refraction** — light bending through a
  layer — plus richer specular and preview controls. Refraction is the one
  glass knob the earlier automated iterations couldn't try, and it may be
  exactly the "more glassy" this icon wants. One caution: v2-only effects
  target iOS 27; a phone on iOS 26 may not render them, so anything refraction
  gives you in the canvas must still pass the on-device check before you
  count on it.

## 2. Open the document

Work on a branch. Then double-click `WorkoutTracker/AppIcon.icon` (or File →
Open in Icon Composer). The window has three parts:

- **Left sidebar** — the layer tree. You'll see one group, **Sun disc**,
  containing one layer, **sunbird** (the SVG). Glass material properties live
  on the *group*; the fill color lives on the *layer*.
- **Center canvas** — the live-rendered icon. Bottom-right toggles switch the
  appearance being previewed: **Default** (light), **Dark**, **Mono**.
- **Right inspector** — the controls for whatever is selected. Menus above
  each control group let a setting apply to **All** appearances or just the
  one being previewed. The existing documents specialize only the *colors*
  per appearance; the glass physics apply to All — keep it that way unless an
  appearance clearly needs its own value.

## 3. What's already dialed in (the shipping state)

Selecting the **Sun disc** group shows the current material settings —
"build 12" from the tuning ledger below:

- Specular: **off**
- Shadow: **neutral, 0.3**
- Translucency: **on, 0.25**
- Blur / frost: none
- Layer **sunbird**: Liquid Glass on, solid fill per the color table above,
  with a dark-appearance color specialization

The background (select the icon root / canvas with nothing else selected) is
a vertical linear gradient, also specialized for dark.

## 4. The tuning ledger — learn from builds 9–12

Four TestFlight builds bracketed the dial without landing it:

| Build | Physics | Verdict on the phone |
|---|---|---|
| 9 | specular on, shadow 0.5, translucency 0.5 | washed out, embossed ("raised plastic") |
| 10 | specular off, shadow 0.3, translucency 0.25 | better, but flat and muddy |
| 11 | specular on, shadow 0.3, translucency 0.4, blur 0.4 | color ✓, everything else a regression |
| 12 | build-10 physics + vivid amber | shipping state — solid, wants more glass |

What that history says about each slider:

- **Move one slider at a time.** Blind combinations are what burned builds 9
  and 11; with live preview you don't have to guess.
- **Specular**: turn it back **on** first. It embossed only in combination
  with heavy shadow + high translucency; on its own it's the crisp edge
  highlight that reads as glass.
- **Translucency**: try ~0.35–0.4. Above ~0.4 is what washed out build 9.
- **Blur / frost**: 0.4 was the main regression ingredient in build 11. If
  you add any, start ≤ 0.2.
- **Shadow**: leave at neutral ~0.3; 0.5 contributed to the embossed look.
- **Refraction** (new in v2): untried territory. Start subtle and remember
  the iOS 26 caveat from step 1.

## 5. Preview before you commit

- Check **Default and Dark** on every change — the fills specialize per
  appearance, but the physics are shared, so a tweak that flatters light mode
  can regress dark.
- Glance at **Mono** too; it should stay legible, though the raster tinted
  fallback also covers it.
- Use the size waterfall and background previews to confirm the mark holds up
  small and against busy wallpapers.
- **Canvas vs. device**: this document uses an SVG layer. Some Icon Composer
  builds have shown SVG layers without full glass in the GUI canvas even
  though `actool`/device rendering is correct — and builds 9–12 verified real
  Liquid Glass on device from these exact files. If the canvas looks oddly
  flat, suspect the preview before the document.

## 6. Save, mirror, ship

1. **File → Save** — *not* Export (Export produces flattened PNGs for
   marketing, not the `.icon` document).
2. Repeat the same physics changes in `AppIconDev.icon`. The two documents
   differ by hue only; their material settings should stay identical.
3. Don't rename the bundles or the layer asset — the `APPICON_NAME` flavor
   flip and the fallback pairing are name-based.
4. Icon Composer may reformat `icon.json` on save; that churn is fine —
   commit whatever it writes.
5. Commit both bundles, push, and get it on the phone: a `testflight`-labeled
   PR produces a WT Dev build ([#356](https://github.com/Sunnshiine/workout-app/issues/356)
   pipeline). The home screen is the real gate — close
   [#373](https://github.com/Sunnshiine/workout-app/issues/373) when the
   glass looks right there.

## Sources

- [Icon Composer — Apple Developer](https://developer.apple.com/icon-composer/)
- [Icon Composer 2 and SF Symbols 8 now available as betas — 9to5Mac](https://9to5mac.com/2026/06/12/icon-composer-2-and-sf-symbols-8-now-available-as-betas/)
- [WWDC26: Icon Composer for Beginners — Q&A](https://antongubarenko.substack.com/p/wwdc26-icon-composer-for-beginners)
- [Icon Composer notes — Virtual Sanity](https://www.virtualsanity.com/202507/icon-composer-notes/) (UI layout, Save-vs-Export, SVG canvas gotcha)
- [Adding Icon Composer icons to Xcode — Use Your Loaf](https://useyourloaf.com/blog/adding-icon-composer-icons-to-xcode/)
