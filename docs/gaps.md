# Gaps

Pick the top item that belongs to the current phase in `docs/STATUS.md`. Do not start a later phase early.

## This phase

1. W3. Add `scripts/ci.sh`, `.githooks/pre-commit`, and `.github/workflows/ci.yml`. Record the first full gate run.

## Later, in order

2. W4. Crash bans, hostile-input bounds, iterative evaluation, and a crash-safe recovery copy. Each fix gets a regression test.
3. W5. Private corpus (`SPARK_GRID_CORPUS`), saved-result answer check, ledger ground truth, fuzz smoke, and unit tests for every function marked done in `docs/function-parity.md`.
4. W6. `spark-grid-cli` with `eval`, `cat`, `recalc`, `check`, `bench`, and `run`.
5. W7. Engine command registry. Move `cell.set`, paste, fill, insert and delete rows and columns, sort, undo, redo, and sheet add, rename, and delete first. Also move `SpreadsheetDocumentStore` and `SpreadsheetViewModel` command work out of the app target. They stayed in the app in W2 because `Engine` cannot import AppKit.
6. W8. `scripts/check-privacy.sh`, `scripts/check-assets.sh`, and `ATTRIBUTION.md`. Remove tracked KPI-derived `scripts/answers/reference-answers.txt` without committing any of its values.
7. Correct answers, after the gates exist. Range reads must use calculated precedents. `TEXT` must follow the format code. Long formula chains must evaluate iteratively. The only known saved-result exception to record later is a malformed formula on the KPI file whose saved result is `#ERROR!`. Do not special-case that cell in the engine.
