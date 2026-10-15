# Gaps

Pick the top item that belongs to the current phase in `docs/STATUS.md`. Do not start a later phase early.

## This phase

1. W5. Private corpus (`SPARK_GRID_CORPUS`), saved-result answer check (`AnswerCheck`), ledger ground truth, fuzz smoke (`CommandFuzz`), and unit tests for every function marked present in `docs/function-parity.md`.

## Later, in order

2. W6. `spark-grid-cli` with `eval`, `cat`, `recalc`, `check`, `bench`, and `run`.
3. W7. Engine command registry. Move `cell.set`, paste, fill, insert and delete rows and columns, sort, undo, redo, and sheet add, rename, and delete first. Also move `SpreadsheetDocumentStore` and `SpreadsheetViewModel` command work out of the app target. They stayed in the app in W2 because `Engine` cannot import AppKit.
4. W8. Write `ATTRIBUTION.md` and clear `scripts/check-privacy.sh` without committing customer values. Remove tracked KPI-derived `scripts/answers/reference-answers.txt`. The privacy and asset scripts already exist and fail.
5. Correct answers, after the gates exist. Range reads must use calculated precedents. `TEXT` must follow the format code. Long formula chains must evaluate iteratively. The only known saved-result exception to record later is a malformed formula on the KPI file whose saved result is `#ERROR!`. Do not special-case that cell in the engine.
