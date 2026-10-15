# Status

Updated: 2026-10-15. Commit this file in the same commit as the work it describes.

## Phase

Workflow gates, W3. The commit gate is in the tree and does not pass. W4 through W8 are not started. Phase A (correct answers) is paused and has no commits.

## Next task

W4. Clear the SwiftLint crash-rule violations. The gate stops there. Do not disable a rule.

## Last gate result

2026-10-15. `scripts/ci.sh` printed `FAIL (0.6s)`. It stopped at lint. SwiftLint 0.65.1 strict, 100 Swift files, 13 violations: 8 `force_unwrapping`, 2 `fatalError`, 1 `implicitly_unwrapped_optional`, 1 subscript `]!`, 1 `precondition(`. No `force_try`, `force_cast`, `assert(`, `unowned`, or `preconditionFailure(` in that run. Later stages did not run.

Independent checks, not part of the 0.6s: `swift-format lint -s` failed with 9266 findings. `scripts/check-layers.sh` passed. Privacy failed on the tracked spreadsheets outside `Fixtures/`, on `scripts/answers/reference-answers.txt`, and on `web/images/hero.png` (over 1 MB, allowlist empty). Assets failed because `ATTRIBUTION.md` is missing. Ledger failed because `AnswerCheck` is not built. KPI skipped because `SPARK_GRID_CORPUS` is unset. Fuzz failed because `CommandFuzz` is not built. There is no full PASS.

Answer check on 2026-10-15, scalar evaluator against displayed values, KPI workbook, commit `2958120`: 48191 formulas, 11894 mismatches. The ledger scalar check did not finish. This scalar check is not ground truth. Not re-run for W3.

## Latest Release numbers

Date: 2026-10-15. Binary: Release build of `2958120`. Machine: this Mac. W3 did not change engine or UI code, so these numbers are still the baseline.

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
