# Status

Updated: 2026-10-15. Commit this file in the same commit as the work it describes.

## Phase

Workflow gates, W6. `spark-grid-cli` can eval, cat, recalc, check, bench, and run commands. W7 and W8 are not started. Phase A (correct answers) is paused and has no commits.

## Next task

W7. Move the view-model actions onto `WorkbookSession`.

## Last gate result

2026-10-15, after W6. Ledger ground truth: 1646 formulas, 0 mismatches. KPI saved-result check: 48191 formulas, 367 mismatches, 1 exempt. Fuzz smoke: seed 1, 20 steps, pass. `spark-grid-cli eval '=ABS(-2)'` prints `2`. Full `scripts/ci.sh` still stops at privacy and assets until W8. KPI skips when `SPARK_GRID_CORPUS` is unset. Do not weaken those stages. The 367 KPI mismatches stay mismatches.

Independent checks, not part of the 0.6s: `swift-format lint -s` failed with 9266 findings. `scripts/check-layers.sh` passed. Privacy failed on the tracked spreadsheets outside `Fixtures/`, on `scripts/answers/reference-answers.txt`, and on `web/images/hero.png` (over 1 MB, allowlist empty). Assets failed because `ATTRIBUTION.md` is missing. Ledger failed because `AnswerCheck` is not built. KPI skipped because `SPARK_GRID_CORPUS` is unset. Fuzz failed because `CommandFuzz` is not built. There is no full PASS.

Answer check on 2026-10-15, saved results cleared and recalculated, KPI workbook: 48191 formulas, 367 mismatches, 1 exempt. Ledger ground truth the same day: 1646 formulas, 0 mismatches. The older scalar check on `2958120` was 48191 formulas and 11894 mismatches. That scalar check is not ground truth.

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
