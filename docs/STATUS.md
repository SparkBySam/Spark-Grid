# Status

Updated: 2026-10-16. Commit this file in the same commit as the work it describes.

## Phase

Phase A is in progress. A formula cell inside a range is calculated before that range is read. The four answer-check paths are not at 0 yet.

## Next task

Correct answers. Every answer-check path must reach 0 mismatches except `YTD Summary!R5`. `TEXT` date and time codes are next.

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

Range reads now calculate formula cells in the range before the range is assembled. Same day, Release, same machine, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 896 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 2,118 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 896 | 1 |
| Full recalculation | 367 | 1 |

Full recalculation is unchanged at 367 plus the exempt cell. Paint order and the edit path dropped from 9,915. The shuffled path dropped from 32,833. The check still fails until every path is 0 mismatches except `YTD Summary!R5`.

## Latest Release numbers

Date: 2026-10-16. Binary: Release build on `cursor/workflow-gates` after range reads calculate before the range is read. Machine: this Mac. Edit to pixels starts at `commitEdit` and stops when that display pass returns. The painted count is cells drawn in that pass.

KPI reference file:

| Path | Release |
|---|---|
| Import | 0.367 s |
| Fingerprint | 3.904 s |
| Export | 2.191 s |
| Autosave on the main thread | 0.000 s |
| Open | 0.643 s |
| Unsaved-changes check | 0.000 s |
| Slowest first screen | 0.057 s (May) |
| June scroll, worst screen | 0.135 s (13 ticks) |
| Tab switch | 0.000 s |
| One edit commit | 0.003 s (YTD Summary!A1) |
| Edit to pixels | 0.046 s, 1452 cells painted |
| Resident memory | ~305 MB |

Synthetic ledger:

| Path | Release |
|---|---|
| Import | 0.560 s |
| Fingerprint | 0.441 s |
| Export | 0.846 s |
| Open | 3.585 s |
| Slowest first screen | 1.078 s (IndexMatch) |
| Scroll, worst screen | 0.675 s (7 ticks) |
| Tab switch | 0.000 s |
| One edit commit | 0.190 s (Ledger!C2) |
| Edit to pixels | 3.284 s, 92 cells painted |
| Resident memory | ~821 MB |

Previous Release run, 2026-10-16, after the edit-to-pixels measurement and before range reads: KPI open 0.681 s, one edit commit 0.003 s, edit to pixels 0.046 s (1452 cells), June scroll worst 0.132 s (13 ticks), export 2.251 s. Ledger open 3.598 s, one edit commit 0.160 s, edit to pixels 3.281 s (92 cells), scroll worst 0.605 s (7 ticks), export 0.827 s. Older baseline (2026-10-11) is in `.cursor/rules/performance.mdc`. Use the table above when a commit needs before/after numbers, and replace it when a new Release run finishes.
