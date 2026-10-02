# Spark Grid

Native macOS spreadsheet for opening, editing, and saving Excel `.xlsx` and CSV files.

Built with SwiftUI chrome and a custom AppKit grid — formulas, formatting, filters, conditional formatting, charts, and embedded images.

**Version 1.0** — first public release candidate. Expect rough edges versus Excel/Numbers; please report issues.

## Requirements

- macOS 14+ (tested on macOS 27 Golden Gate)
- Xcode 27+ recommended to build against the macOS 27 SDK (older Xcode 16+ may still work for source builds)
- Apple Development / Distribution signing team

## Build & run

```bash
open "Spark Grid.xcodeproj"
```

Or:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme "Spark Grid" -configuration Release -destination 'platform=macOS' build
```

## Features

- Spreadsheet grid: selection, fill handle, freeze panes, merges, zoom
- Formula bar with lexer/parser/evaluator and autocomplete
- Formatting toolbar, conditional formatting, AutoFilter, sort, find/replace
- Charts with an insert chooser (category + values or count-by-category)
- Embedded pictures (insert, move, resize, z-order)
- `.xlsx` / `.csv` open & save with autosave
- Finder Quick Look: press **Space** on a `.csv` / `.tsv` / `.xlsx` to preview the grid, edit cells, and save (or open in Spark Grid)

### Enabling Finder Quick Look after a build

1. Open `Spark Grid.xcodeproj` and **Product → Run** the **Spark Grid** scheme once (this embeds `Spark Grid Quick Look.appex`).
2. Register / prefer the extension (searches `/Applications`, repo build folders, and DerivedData):

```bash
./scripts/register-quicklook.sh
# or: ./scripts/register-quicklook.sh "/path/to/Spark Grid.app"
```

3. In Finder, select a `.csv` / `.xlsx` and press **Space**. The preview chrome should show **Save** and **Open in Spark Grid**.

If the script says the appex is missing, you haven’t built this branch yet — Run from Xcode first. If Space still shows plain text: `pluginkit -mAvvv -p com.apple.quicklook.preview | grep -i Spark` then `qlmanage -r && killall Finder`.

## App Store / signing notes

- Bundle ID: `com.sparkbysam.SparkGrid`
- Sandboxed; user-selected file access + printing
- No network features; encryption questionnaire: standard exemption (`ITSAppUsesNonExemptEncryption = false`)
- Privacy Nutrition Labels: data not collected (confirm in App Store Connect)

## Debug bug-bash

```bash
export SPARK_GRID_BUG_BASH=1
export SPARK_GRID_FIXTURES="/path/to/fixtures"   # optional
# formulas.xlsx, conditional_format.xlsx, enterprise_themed.xlsx, enterprise_images.xlsx
```

Missing fixtures are skipped.

## Project layout

| Area | Location |
|------|----------|
| App / window | `Spark Grid/App`, `Spark Grid/Views` |
| Grid | `Spark Grid/Grid` |
| State | `Spark Grid/State` |
| Shared models / formulas / XLSX+CSV | `Spark Grid Shared/` |
| Finder Quick Look | `Spark Grid Quick Look/` |

## License

Copyright © 2026 Sam Parker. All rights reserved.
