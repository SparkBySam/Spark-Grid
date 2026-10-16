# Roadmap

## Stage

Workflow gates W1–W6 are committed. The gate still fails at privacy and assets. Ledger ground truth is 1646 formulas, 0 mismatches. KPI saved-result check is 48191 formulas, 367 mismatches, 1 exempt. Correctness and lag work stays paused. Version on this branch: 1.2.0 (5).

## Headline numbers

Release, 2026-10-15, commit `2958120`, KPI file: import 0.358 s, open 0.580 s, export 2.282 s, fingerprint 3.922 s, June scroll worst 0.146 s, one edit 0.004 s. Saved-result answer check: 48191 formulas, 367 mismatches, 1 exempt. Ledger ground truth: 1646 formulas, 0 mismatches.

## Progress log

- 2026-10-15 — W6: `spark-grid-cli` eval, cat, recalc, check, bench, and run. Smoke: `eval '=ABS(-2)'` prints `2`. Full gate still blocked by privacy and assets.
- 2026-10-15 — W5: corpus manifest (hash only), ledger Python ground truth (1646 formulas, 0 mismatches), KPI saved-result check (48191 formulas, 367 mismatches, 1 exempt), fuzz smoke (seed 1, 20 steps, pass), unit tests for every present function. Full gate still blocked by privacy and assets.
- 2026-10-15 — W4: crash-rule violations removed, hostile-input caps added, recovery copy written after edits. SwiftLint and swift-format pass. Full gate still blocked by later stages.
- 2026-10-15 — W3: `scripts/ci.sh` is the commit gate. First run `FAIL (0.6s)` at SwiftLint 0.65.1 strict (13 violations). No full PASS.
- 2026-10-15 — W2: engine moved into `Packages/SparkGridCore` with nine layers. Layer check passed. Gate script still not built.
- 2026-10-15 — W1: agent rulebook, status, gaps, and function parity. Gate not built yet.
- 2026-10-15 — `2958120`: sheet switch returns before cross-sheet calc; save returns before the export write finishes. Viewport scroll and Find focus stay.
- 2026-10-11 — Performance rules and the older KPI baseline recorded on `main`.
