# App icon sources

The **Sunbird** mark: a soaring bird as pure negative space in a glass sun
disc. Direction decided in
[#370](https://github.com/Sunnshiine/workout-app/issues/370), assets produced
in [#369](https://github.com/Sunnshiine/workout-app/issues/369).

| Source | Rendered into | Treatment |
|---|---|---|
| `appicon-light.svg` | `AppIcon.appiconset/Icon-1024.png` | deep-green glass on sage (L1) |
| `appicon-dark.svg` | `AppIcon.appiconset/Icon-1024-dark.png` | mint glass on Midnight |
| `appicon-tinted.svg` | both sets' `Icon-1024-tinted.png` | grayscale on transparent (system tints) |
| `appicon-dev-light.svg` | `AppIconDev.appiconset/Icon-1024.png` | amber glass on sand (WT Dev) |
| `appicon-dev-dark.svg` | `AppIconDev.appiconset/Icon-1024-dark.png` | amber glass on warm midnight (WT Dev) |

The dev flavor differs by hue only (amber "dawn" vs. stable green): letters
and badges were ruled out with the #370 mark decision, and a hue flip is the
treatment that stays legible at every size.

These SVGs are the canonical artwork — the asset-catalog PNGs are build
products of `scripts/generate-app-icons.sh` (Chromium is the reference
rasterizer). Edit the SVGs and re-render; never retouch the PNGs.

The true glass icons are the hand-authored Icon Composer documents
`WorkoutTracker/AppIcon.icon` and `WorkoutTracker/AppIconDev.icon` (#373):
one monochrome disc-with-bird-cutout SVG layer whose fill and background
gradient specialize per appearance (light/dark), with the system glass
material replacing the baked glow/rim/sheen. iOS 26 renders those; the
raster sets above are the back-deploy fallback
(`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` keeps both in the build).
