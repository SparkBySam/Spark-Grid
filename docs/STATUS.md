# Status

Updated: 2026-10-16. Commit this file in the same commit as the work it describes.

## Phase

Workflow gates, W8, are in. The answer check now walks four paths. Phase A (correct answers) is not started.

## Next task

Correct answers. Every answer-check path must reach 0 mismatches except `YTD Summary!R5`. Not started.

## Last gate result

2026-10-16, after W8. `scripts/ci.sh` printed `PASS (215.3s)`. Lint, format, package, xcodebuild, layers, privacy-assets, ledger, and fuzz passed. KPI skipped because `SPARK_GRID_CORPUS` was unset. That skip is not a local pass anymore. `scripts/ci.sh` sets `SPARK_GRID_CORPUS` when the manifest file is in `~/Downloads` or `~/SparkGridCorpus`, and a skipped KPI stage fails the local gate. Hosted CI still skips KPI. Ledger ground truth the same day: 1646 formulas, 0 mismatches. Fuzz smoke: seed 1, 20 steps, pass.

The real KPI baseline is the display path, not full recalculation. On 2026-10-16, against the original saved results with caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 9,915 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 32,833 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 9,915 | 1 |
| Full recalculation | 367 | 1 |

Paint order differs in 9,916 formulas. That count is the 9,915 mismatches plus the one exempt cell, `YTD Summary!R5`. Record 9,916 as the baseline. The check still fails until every path is 0 mismatches except that cell. Do not weaken it. An earlier unseeded random walk differed in 32,571; the gate uses seed 1. Full recalculation differed in 368, which is 367 plus the exempt cell. The scalar check on `2958120` was 11,894 mismatches and is not ground truth.

## Latest Release numbers

Date: 2026-10-16. Binary: Release build on `cursor/workflow-gates` after W7's edit path, with edit-to-pixels measured through the next `display()`. Machine: this Mac. Edit to pixels starts at `commitEdit` and stops when that display pass returns. The painted count is cells drawn in that pass.

KPI reference file:

| Path | Release |
|---|---|
| Import | 0.364 s |
| Fingerprint | 3.773 s |
| Export | 2.251 s |
| Autosave on the main thread | 0.000 s |
| Open | 0.681 s |
| Unsaved-changes check | 0.000 s |
| Slowest first screen | 0.054 s (December) |
| June scroll, worst screen | 0.132 s (13 ticks) |
| Tab switch | 0.000 s |
| One edit commit | 0.003 s (YTD Summary!A1) |
| Edit to pixels | 0.046 s, 1452 cells painted |
| Resident memory | ~306 MB |

Synthetic ledger:

| Path | Release |
|---|---|
| Import | 0.519 s |
| Fingerprint | 0.424 s |
| Export | 0.827 s |
| Open | 3.598 s |
| Slowest first screen | 1.114 s (IndexMatch) |
| Scroll, worst screen | 0.605 s (7 ticks) |
| Tab switch | 0.000 s |
| One edit commit | 0.160 s (Ledger!C2) |
| Edit to pixels | 3.281 s, 92 cells painted |
| Resident memory | ~1327 MB |

Previous Release run, 2026-10-15, commit `2958120`: KPI open 0.580 s, one edit commit 0.004 s, June scroll worst 0.146 s (13 ticks), export 2.282 s. Ledger open 3.550 s, one edit commit 0.132 s, scroll worst 0.628 s (7 ticks), export 0.824 s. Edit to pixels was not measured. Older baseline (2026-10-11) is in `.cursor/rules/performance.mdc`. Use the table above when a commit needs before/after numbers, and replace it when a new Release run finishes.
