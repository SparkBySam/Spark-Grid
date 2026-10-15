# Gaps

Pick the top item that belongs to the current phase in `docs/STATUS.md`. Do not start a later phase early.

## This phase

1. W2. Put the engine in `Packages/SparkGridCore` with layers `GridCore`, `NumberFormat`, `Formula`, `Functions`, `Model`, `Calc`, `FileFormats`, `Engine`, `Rendering`. App and Quick Look build from the package. `swift build` and `swift test` run. `scripts/check-layers.sh` passes. No engine code remains in the app target.
2. W3. Add `scripts/ci.sh`, `.githooks/pre-commit`, and `.github/workflows/ci.yml`. Record the first full gate run.

## Later, in order

3. W4. Crash bans, hostile-input bounds, iterative evaluation, and a crash-safe recovery copy. Each fix gets a regression test.
4. W5. Private corpus (`SPARK_GRID_CORPUS`), saved-result answer check, ledger ground truth, fuzz smoke, and unit tests for every function marked done in `docs/function-parity.md`.
5. W6. `spark-grid-cli` with `eval`, `cat`, `recalc`, `check`, `bench`, and `run`.
6. W7. Engine command registry. Move `cell.set`, paste, fill, insert and delete rows and columns, sort, undo, redo, and sheet add, rename, and delete first.
7. W8. `scripts/check-privacy.sh`, `scripts/check-assets.sh`, and `ATTRIBUTION.md`. Remove tracked KPI-derived `scripts/answers/reference-answers.txt` without committing any of its values.
8. Correct answers, after the gates exist. Range reads must use calculated precedents. `TEXT` must follow the format code. Long formula chains must evaluate iteratively. The only known saved-result exception to record later is a malformed formula on the KPI file whose saved result is `#ERROR!`. Do not special-case that cell in the engine.
