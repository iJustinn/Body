# Replacing Body's app icons with Icon Composer (`.icon`) files

A reusable, verified workflow for swapping Body's app icons — a primary icon plus its
alternates — over to Apple's **Icon Composer** (`.icon`) format introduced in Xcode 26 /
iOS 26. The `.icon` format gives you layered icons that render with the iOS 26 light / dark /
tinted (Liquid Glass) appearances, and Xcode auto-generates a flat raster fallback for older
OS versions.

This is the exact process used to replace Body's six icons — **Classic, Rose, Violet,
Midnight, Neutral, Light** — and to give the `BodyWatch` and `BodyWidgetExtension` targets the
matching primary icon. The editable source `.icon` files live in this `Icons/` folder; the
copies under each target are the build inputs. The workflow generalizes to any app — adapt the
names — but every example below is Body's real setup.

---

## The one idea that makes this painless

**Name each `.icon` file exactly the same as the app-icon name it replaces.**

App icons are referenced *by name* in two build settings and (for alternates) by string at
runtime via `setAlternateIconName(_:)`. If your new `.icon` files keep those same names, you
change **zero** Swift code and **zero** build settings — you only swap files. If you rename
the icons, you must update the build settings, the runtime strings, and any UI labels too.

| What references the icon | Where | Uses the name… |
|---|---|---|
| Primary icon | `ASSETCATALOG_COMPILER_APPICON_NAME` build setting | without extension (`AppIcon`) |
| Alternate icons | `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` build setting | space-separated, no extension (`BodyBlack BodyGray …`) |
| Runtime switching | `UIApplication.shared.setAlternateIconName("BodyPink")` | alternate name; `nil` = primary |
| In-app picker preview | `BodyAppIconOption.previewAssetName` in `BodySettingsView.swift` | a separate `BodyIcon*` imageset |

---

## Prerequisites

- **Xcode 26+** (`xcodebuild -version`). The `.icon` format and `actool`'s `.icon` support
  require it.
- One **`.icon` file per app icon**, exported from Icon Composer. Each is a folder bundle
  containing `icon.json` + an `Assets/` folder of layer PNGs. Body keeps these in `Icons/`.
- Know your current icon names. Find them with:
  ```bash
  grep -nE "ASSETCATALOG_COMPILER_(APPICON_NAME|ALTERNATE_APPICON_NAMES)" Body.xcodeproj/project.pbxproj
  ```
  For Body they are:
  ```
  ASSETCATALOG_COMPILER_APPICON_NAME            = AppIcon
  ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "BodyBlack BodyGray BodyPink BodyPurple BodyWhite"
  ```

---

## Step 1 — Map new files to existing names

List the existing names (primary first, then alternates) and decide which new `.icon` maps
to each. Body's mapping (the picker display name is in `BodyAppIconOption.standard`):

| Source file (`Icons/`) | → existing app-icon name | picker label / descriptor | picker preview imageset |
|---|---|---|---|
| `Body-Classic.icon` | `AppIcon` (primary) | Classic / Original | `BodyIcon01` |
| `Body-Pink.icon`    | `BodyPink`          | Rose / Pink         | `BodyIconPink` |
| `Body-Purple.icon`  | `BodyPurple`        | Violet / Purple     | `BodyIconPurple` |
| `Body-Black.icon`   | `BodyBlack`         | Midnight / Black    | `BodyIconBlack` |
| `Body-Gray.icon`    | `BodyGray`          | Neutral / Gray      | `BodyIconGray` |
| `Body-White.icon`   | `BodyWhite`         | Light / White       | `BodyIconWhite` |

## Step 2 — Add the `.icon` files to the targets (renamed)

`.icon` files go **directly in the project / target — NOT inside `.xcassets`.**

The `Body`, `BodyWatch`, and `BodyWidgetExtension` targets all use **synchronized folder
groups** (Xcode 16+, the default — look for `PBXFileSystemSynchronizedRootGroup` in
`project.pbxproj`), so just copy the renamed files into each target's folder on disk and
they're picked up automatically — no `project.pbxproj` editing.

Main `Body` app — primary + all five alternates:
```bash
cp -R Icons/Body-Classic.icon Body/AppIcon.icon      # primary
cp -R Icons/Body-Pink.icon    Body/BodyPink.icon
cp -R Icons/Body-Purple.icon  Body/BodyPurple.icon
cp -R Icons/Body-Black.icon   Body/BodyBlack.icon
cp -R Icons/Body-Gray.icon    Body/BodyGray.icon
cp -R Icons/Body-White.icon   Body/BodyWhite.icon
```

Watch app and widget extension — primary only (they ship no alternates):
```bash
cp -R Icons/Body-Classic.icon BodyWatch/AppIcon.icon
cp -R Icons/Body-Classic.icon BodyWidgetExtension/AppIcon.icon
```
(Renaming the `.icon` folder is safe — `icon.json` references its own layers, not its own
name.)

## Step 3 — Remove the old icon assets

Delete the old `.appiconset` folders from the asset catalog (keep everything else — colors,
image sets, the `BodyIcon*` picker previews, etc.):
```bash
rm -rf Body/Assets.xcassets/{AppIcon,BodyBlack,BodyGray,BodyPink,BodyPurple,BodyWhite}.appiconset
rm -rf BodyWatch/Assets.xcassets/AppIcon.appiconset
rm -rf BodyWidgetExtension/Assets.xcassets/AppIcon.appiconset
```
Sweep any leftover legacy `*Alt.appiconset` sets from earlier icon schemes at the same time.

## Step 4 — Build settings (usually already correct)

Confirm these on the `Body` target; if you kept the names, they need **no change**:
```
ASSETCATALOG_COMPILER_APPICON_NAME            = AppIcon
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "BodyBlack BodyGray BodyPink BodyPurple BodyWhite"
```
Every name listed in `ALTERNATE_APPICON_NAMES` is what makes that alternate ship — keep the
list in sync with the alternates you provide. `BodyWatch` / `BodyWidgetExtension` only set
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` (no alternates).

> Body does **not** set `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`; the explicit
> `ALTERNATE_APPICON_NAMES` list already ships every alternate. (Only turn `INCLUDE_ALL` on
> if you want *every* `.icon` in the target shipped without listing them.)

> No `Info.plist` keys are needed — `actool` generates `CFBundlePrimaryIcon` /
> `CFBundleAlternateIcons` from the build settings at compile time. (You only resort to
> manual `Info.plist` `CFBundleIcons` entries if you deliberately keep *both* a legacy
> `.appiconset` and a same-named `.icon` for crisp back-deployment; that's not this flow.)

## Step 5 — Regenerate the in-app picker previews

Body's Settings icon picker (`BodyAppIconOption` in `BodySettingsView.swift`) shows its own
thumbnails from separate `BodyIcon*` imagesets — there's no public API to render an alternate
icon to a `UIImage`. Regenerate each from the new artwork. `actool` flattens any `.icon` to a
faithful raster — use that as the preview source:

```bash
# Flatten one .icon -> PNG. The bundle must be named to match --app-icon.
work=$(mktemp -d); cp -R Body/BodyPink.icon "$work/AppIcon.icon"
xcrun actool --compile "$work/out" --platform iphoneos --minimum-deployment-target 18.0 \
  --app-icon AppIcon --output-partial-info-plist "$work/out/p.plist" \
  --target-device iphone --target-device ipad "$work/AppIcon.icon"
# Largest loose output is the iPad @2x (152px); the iPhone @2x is 120px:
cp "$work/out/AppIcon76x76@2x~ipad.png" \
   Body/Assets.xcassets/BodyIconPink.imageset/BodyIconPink.png
```
Repeat for each option, writing to its `previewAssetName` imageset: `BodyIcon01` (Classic),
`BodyIconPink`, `BodyIconPurple`, `BodyIconBlack`, `BodyIconGray`, `BodyIconWhite`.

Notes:
- `actool`'s loose output tops out at 152px (the full 1024 render stays inside the compiled
  `Assets.car`). 152px is plenty for a small thumbnail; if you need a hero/marketing image,
  export it from Icon Composer instead.
- `qlmanage` can hang headless — don't rely on it in scripts.

## Step 6 — Build and verify

```bash
xcodebuild -project Body.xcodeproj -scheme Body \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
```

In the build log you should see `actool` invoked with every `.icon` discovered and the
right flags:
```
--app-icon AppIcon \
--alternate-app-icon BodyBlack --alternate-app-icon BodyGray \
--alternate-app-icon BodyPink --alternate-app-icon BodyPurple --alternate-app-icon BodyWhite …
```

Then confirm the built product (`<DerivedData>/…/Body.app`):
```bash
# 1) Primary + alternates registered in the generated Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleIcons" Body.app/Info.plist
#    → CFBundlePrimaryIcon = AppIcon, CFBundleAlternateIcons = { BodyBlack, BodyGray, … }

# 2) Every icon present at 1024, each with light/dark/tinted appearances
xcrun assetutil --info Body.app/Assets.car | grep -E '"Name"|"PixelHeight"|Appearance'
#    → AppIcon/BodyBlack/… each at PixelHeight 1024 with
#      UIAppearanceAny / UIAppearanceDark / ISAppearanceTintable
```
The presence of the three appearances confirms you got the layered iOS 26 treatment (not a
flat PNG). The loose `AppIcon60x60@2x.png` emplaced in the bundle is the iOS 18–25 fallback.

## Step 7 — Update docs / references

Anything that pointed at the deleted `.appiconset` PNG path (e.g. a README `<img>`) must be
repointed — those files are gone.

---

## How runtime icon switching works (unchanged)

```swift
// nil → primary AppIcon.icon; a name → that alternate .icon
UIApplication.shared.setAlternateIconName(option.alternateIconName) { _ in }
```
Because the `.icon` files reuse the old names, Body's `BodyAppIconOption` / settings code keeps
working verbatim.

## Caveats

- **Back-deployment (iOS 18–25):** the layered glass look is iOS 26+. On older systems iOS
  uses the flat raster `actool` auto-generates from the `.icon`. That's automatic with this
  clean-replace flow. If you instead need a *hand-tuned* legacy icon, keep the old
  `.appiconset` alongside a same-named `.icon` and set
  `ASSETCATALOG_OTHER_FLAGS = --enable-icon-stack-fallback-generation=disabled`.
- **`.icon` files do not belong inside `.xcassets`.** Put them at the target root.
- **Keep the source `.icon` files** in this `Icons/` folder as the editable design source; the
  copies under each target are the build inputs.

## Checklist

- [ ] Xcode 26+, one `.icon` per app icon (Body's six in `Icons/`)
- [ ] Renamed each `.icon` to its existing primary/alternate name
- [ ] Copied into each target (synced folder = automatic): `Body` (all six), `BodyWatch` + `BodyWidgetExtension` (`AppIcon` only)
- [ ] Deleted old `.appiconset`s (incl. leftover `*Alt`)
- [ ] Build settings unchanged (names matched); `ALTERNATE_APPICON_NAMES` lists all five alternates
- [ ] Regenerated the `BodyIcon*` picker previews
- [ ] Build succeeds; `Info.plist` + `Assets.car` verified
- [ ] Repointed any docs that referenced old icon paths
