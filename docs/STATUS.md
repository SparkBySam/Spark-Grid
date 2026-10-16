# Status

Updated: 2026-10-16. Commit this file in the same commit as the work it describes.

## Phase

Workflow gates, W8. Privacy and asset checks pass. `ATTRIBUTION.md` lists the app icon and the package licenses. Phase A (correct answers) is not started.

## Next task

Correct answers. Range reads must use calculated precedents. Not started.

## Last gate result

2026-10-16, after W8. `scripts/ci.sh` printed `PASS (215.3s)`. Lint, format, package, xcodebuild, layers, privacy-assets, ledger, and fuzz passed. KPI skipped because `SPARK_GRID_CORPUS` was unset. With the corpus set, the KPI check fails and stays failed: 48191 formulas, 367 mismatches, 1 exempt. Do not weaken that check. Ledger ground truth the same day: 1646 formulas, 0 mismatches. Fuzz smoke: seed 1, 20 steps, pass.

Answer check on 2026-10-16, saved results cleared and recalculated, KPI workbook: 48191 formulas, 367 mismatches, 1 exempt. Ledger ground truth the same day: 1646 formulas, 0 mismatches. The older scalar check on `2958120` was 48191 formulas and 11894 mismatches. That scalar check is not ground truth.

## Latest Release numbers

Date: 2026-10-15. Binary: Release build of `2958120`. Machine: this Mac. W4 changes crash paths, not the timed open/save/scroll paths. These numbers stay the baseline until a new Release run.

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
