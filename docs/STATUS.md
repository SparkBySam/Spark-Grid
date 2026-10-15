# Status

Updated: 2026-10-15. Commit this file in the same commit as the work it describes.

## Phase

Workflow gates, W2. The engine is in `Packages/SparkGridCore`. W3 (the commit gate) is next. W4 through W8 are not started. Phase A (correct answers) is paused and has no commits.

## Next task

W3. Add `scripts/ci.sh`, `.githooks/pre-commit`, and `.github/workflows/ci.yml`. Run the gate and record the result.

## Last gate result

`scripts/ci.sh` does not exist yet. `scripts/check-layers.sh` passed. `swift build`, `swift build -c release`, and `swift test` in `Packages/SparkGridCore` passed (1 test). Debug and Release `xcodebuild` of the app scheme passed.

Answer check on 2026-10-15, scalar evaluator against displayed values, KPI workbook, commit `2958120`: 48191 formulas, 11894 mismatches. The ledger scalar check did not finish. This scalar check is not ground truth.

## Latest Release numbers

Date: 2026-10-15. Binary: Release build of `2958120`. Machine: this Mac. No engine code changed in W1, so these numbers are still the baseline.

KPI reference file:

| Path | Release |
|---|---|
| Import | 0.358 s |
| Fingerprint | 3.922 s |
| Export | 2.282 s |
| Autosave on the main thread | 0.000 s |
| Open | 0.580 s |
| Unsaved-changes check | 0.000 s |
| Slowest first screen | 0.056 s |
| June scroll, worst screen | 0.146 s (13 ticks) |
| Tab switch | 0.000 s |
| One edit commit | 0.004 s |
| Resident memory | ~305 MB |

Synthetic ledger:

| Path | Release |
|---|---|
| Import | 0.498 s |
| Fingerprint | 0.420 s |
| Export | 0.824 s |
| Open | 3.550 s |
| Scroll, worst screen | 0.628 s (7 ticks) |
| One edit commit | 0.132 s |
| Resident memory | ~1297 MB |

Older baseline (2026-10-11) is in `.cursor/rules/performance.mdc`. Use the table above when a commit needs before/after numbers, and replace it when a new Release run finishes.
