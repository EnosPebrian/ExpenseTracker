# Branding and Icon Guide

## Concept

The Pilgrim Tracker mark combines a protective shield/compass outline, a rising
journey path, and a restrained gold destination point. It communicates guided
financial progress, trust, and calm organization without currency, bank, chart,
text, or religious imagery.

The built-in image-generation concept prompt specified an original,
vector-friendly premium shield/compass and upward path, three colors, a
16-percent safe zone, no text, and no third-party logo resemblance. The final
geometry was redrawn as deterministic SVG.

## Palette

- Deep navy: `#101828`
- Emerald teal: `#20B486`
- Warm gold: `#D6A84B`

## Master assets

- `assets/branding/pilgrim_tracker_icon.svg`
- `assets/branding/pilgrim_tracker_icon_1024.png`
- `assets/branding/pilgrim_tracker_icon_foreground.svg`
- `assets/branding/pilgrim_tracker_icon_foreground_1024.png`
- `assets/branding/pilgrim_tracker_icon_monochrome.svg`
- `assets/branding/pilgrim_tracker_icon_monochrome_1024.png`

The foreground keeps at least 16 percent safe-zone space before Android's
additional adaptive-icon inset and remains recognizable at 192 and 32 pixels.

## Platform outputs

- Android legacy: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Android adaptive: foreground/monochrome drawables and
  `mipmap-anydpi-v26/ic_launcher.xml`
- Windows: `windows/runner/resources/app_icon.ico`
- Web: `web/favicon.png` and `web/icons/*.png`

## Regeneration

Requirements: Chrome, Dart/Flutter dependencies from `flutter pub get`, and
`flutter_launcher_icons` from dev dependencies.

```powershell
powershell -ExecutionPolicy Bypass -File tool\branding\generate_branding_assets.ps1
```

Pass `-ChromePath` or `-DartExecutable` when those commands are installed in a
non-default location. The script renders the SVG sources at 1024 square and
runs `dart run flutter_launcher_icons` using `flutter_launcher_icons.yaml`.
