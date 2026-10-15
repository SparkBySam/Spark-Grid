# Gaps

Pick the top item that belongs to the current phase in `docs/STATUS.md`. Do not start a later phase early.

## This phase

1. W6. `spark-grid-cli` with `eval`, `cat`, `recalc`, `check`, `bench`, and `run`.

## Later, in order

2. W7. Move the view-model actions onto `WorkbookSession`: `cell.set`, paste, fill, insert and delete rows and columns, sort, undo, redo, and sheet add, rename, and delete. The session already runs those commands for the fuzzer. `SpreadsheetDocumentStore` and `SpreadsheetViewModel` stayed in the app in W2 because `Engine` cannot import AppKit. Panels and the pasteboard stay in the app.
3. W8. Write `ATTRIBUTION.md` and clear `scripts/check-privacy.sh` without committing customer values. Remove tracked KPI-derived `scripts/answers/reference-answers.txt`. The privacy and asset scripts already exist and fail.
4. Correct answers, after the gates exist. Range reads must use calculated precedents. `TEXT` must follow the format code. Long formula chains must evaluate iteratively. The only known saved-result exception today is the malformed formula recorded in `corpus/known-differences.md`. Do not special-case that cell in the engine.
