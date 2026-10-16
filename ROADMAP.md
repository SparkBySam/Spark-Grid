# Roadmap

## Stage

Workflow gates W1–W8 are committed. Ledger ground truth is 1646 formulas, 0 mismatches. The KPI answer check walks four paths and still fails: paint order differs in 9916 formulas (9915 mismatches plus the one exempt cell). Correct answers are next. Version on this branch: 1.2.0 (5).

## Headline numbers

Release, 2026-10-16, this Mac, KPI file: import 0.364 s, open 0.681 s, export 2.251 s, fingerprint 3.773 s, June scroll worst 0.132 s, one edit commit 0.003 s, edit to pixels 0.046 s (1452 cells). Ledger: open 3.598 s, one edit commit 0.160 s, edit to pixels 3.281 s (92 cells), scroll worst 0.605 s. Paint-order answer check: 9916 differ. Ledger ground truth: 1646 formulas, 0 mismatches.

## Progress log

- 2026-10-16 — Release timings after the W7 edit path, including edit to pixels. KPI edit to pixels 0.046 s (1452 cells). Ledger edit to pixels 3.281 s (92 cells). Numbers are in `docs/STATUS.md`.
- 2026-10-16 — W8: `ATTRIBUTION.md`, KPI-derived answer file removed, synthetic samples live under `Fixtures/`, `hero.png` is under 1 MB. `scripts/ci.sh` printed `PASS (215.3s)` with the private KPI check skipped. With the corpus set, KPI is still 48191 formulas, 367 mismatches, 1 exempt.
- 2026-10-15 — W7: view-model cell edits, paste, fill, structure changes, sort, and sheet add, rename, and delete go through `WorkbookSession.apply`. Document undo stays on `UndoManager`. Full gate still blocked by privacy and assets.
- 2026-10-15 — W6: `spark-grid-cli` eval, cat, recalc, check, bench, and run. Smoke: `eval '=ABS(-2)'` prints `2`. Full gate still blocked by privacy and assets.
- 2026-10-15 — W5: corpus manifest (hash only), ledger Python ground truth (1646 formulas, 0 mismatches), KPI saved-result check (48191 formulas, 367 mismatches, 1 exempt), fuzz smoke (seed 1, 20 steps, pass), unit tests for every present function. Full gate still blocked by privacy and assets.
- 2026-10-15 — W4: crash-rule violations removed, hostile-input caps added, recovery copy written after edits. SwiftLint and swift-format pass. Full gate still blocked by later stages.
- 2026-10-15 — W3: `scripts/ci.sh` is the commit gate. First run `FAIL (0.6s)` at SwiftLint 0.65.1 strict (13 violations). No full PASS.
- 2026-10-15 — W2: engine moved into `Packages/SparkGridCore` with nine layers. Layer check passed. Gate script still not built.
- 2026-10-15 — W1: agent rulebook, status, gaps, and function parity. Gate not built yet.
- 2026-10-15 — `2958120`: sheet switch returns before cross-sheet calc; save returns before the export write finishes. Viewport scroll and Find focus stay.
- 2026-10-11 — Performance rules and the older KPI baseline recorded on `main`.
