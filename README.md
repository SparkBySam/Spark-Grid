# Spark Grid

Free native Mac spreadsheet for opening, editing, and saving `.xlsx` and CSV files. [Spark Grid 1.0 is on the Mac App Store](https://apps.apple.com/us/app/spark-grid/id6811196983?mt=12). No account, no analytics, and the app does not use the network.

Site: https://sparkgridapp.com

Built with SwiftUI chrome and a custom AppKit grid.

**Version 1.0** is the Mac App Store release. It evaluates an everyday formula list, and it has filters, formatting, pictures, and a bar, line, or area chart in a side panel. Pivot tables and SUMIF are not in this version. Rough edges are real; please report files that break.

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
- Bar, line, or area chart in a side panel, one series from the selection. Charts already in an Excel file are not imported.
- Embedded pictures (insert, move, resize, z-order)
- `.xlsx` / `.csv` open and save, with autosave for a file you have already saved

Finder’s Space preview does not open Spark Grid for `.csv` or `.xlsx`. macOS uses another app’s Quick Look generator for those types.

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
