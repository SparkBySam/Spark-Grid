# Spark Grid

Native macOS spreadsheet for opening, editing, and saving Excel `.xlsx` and CSV files.

Built with SwiftUI chrome and a custom AppKit grid — formulas, formatting, filters, conditional formatting, charts, and embedded images.

**Version 1.0** — first public release candidate. Expect rough edges versus Excel/Numbers; please report issues.

## Requirements

- macOS 14+
- Xcode 16+ (to build from source)
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
| Models & state | `Spark Grid/Models`, `Spark Grid/State` |
| Formulas | `Spark Grid/Formulas` |
| XLSX / CSV | `Spark Grid/Document` |

## License

Copyright © 2026 Sam Parker. All rights reserved.
