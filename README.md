# Spark Grid

> **Status: WIP** — active prototype / portfolio work-in-progress. APIs, UX, and Excel fidelity are unfinished and may change without notice. Not production software.

Native macOS spreadsheet app with Excel `.xlsx` round-trip.

Spark Grid opens, edits, and saves real workbooks — formulas, formatting, filters, conditional formatting, charts, and embedded images — using a SwiftUI shell and a custom AppKit grid for performance.

## Current focus

Rough edges still being worked through:

- Chart UX (sidebar previews vs on-sheet charts)
- Picture interaction polish
- Selection / scroll behavior
- Broader Excel formula and interchange coverage
- Automated bug-bash against local fixtures

Expect incomplete features, rough edges, and breaking changes.

## Requirements

- macOS 14+ (recommended)
- Xcode 16+
- Apple Development signing team (configured in the Xcode project)

## Build & run

```bash
open "Spark Grid.xcodeproj"
```

Or from the CLI:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme "Spark Grid" -destination 'platform=macOS' build
```

Launch the Debug app from Xcode, or open the product under DerivedData.

## Features (in progress)

- Spreadsheet grid with selection, fill handle, freeze panes, merges, zoom
- Formula bar, lexer/parser/evaluator, autocomplete, named ranges
- Formatting toolbar (fonts, fills, borders, number formats, CF)
- AutoFilter, sort, find/replace, print setup
- Charts (bar / line / area) with sidebar previews
- Embedded pictures (insert, paste, move, resize, z-order)
- `.xlsx` and `.csv` open/save with autosave

## Debug bug-bash

Optional import checks against **local** sample workbooks (not checked into the repo):

```bash
export SPARK_GRID_BUG_BASH=1
export SPARK_GRID_FIXTURES="/path/to/your/fixtures"
# Expected filenames (generic; use copies or symlinks of your samples):
#   formulas.xlsx
#   conditional_format.xlsx
#   enterprise_themed.xlsx
#   enterprise_images.xlsx
```

Or override a single file:

```bash
export SPARK_GRID_FIXTURE_ENTERPRISE="/absolute/path/to/workbook.xlsx"
```

Missing fixtures are skipped (tests still pass).

## Project layout

| Area | Location |
|------|----------|
| App / window | `Spark Grid/App`, `Spark Grid/Views` |
| Grid rendering | `Spark Grid/Grid` |
| Models & state | `Spark Grid/Models`, `Spark Grid/State` |
| Formulas | `Spark Grid/Formulas` |
| XLSX / CSV I/O | `Spark Grid/Document` |
| Bug-bash (DEBUG) | `Spark Grid/Utilities/BugBashRunner.swift` |

## Privacy & security notes

- App Sandbox is enabled; file access is user-selected (+ Downloads) and print.
- Do **not** commit real client workbooks. Keep samples under a local `Fixtures/` folder (gitignored) or outside the repo.
- Bug-bash fixture paths are env-driven so the public tree stays free of personal paths and client filenames.

## License

All rights reserved unless a license file is added to this repository. Work-in-progress code — use / fork at your own risk.
