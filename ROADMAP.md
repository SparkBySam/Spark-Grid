# Roadmap

## Stage

Workflow gates W1–W3. Correctness and lag work waits until this stage is in place. Version on this branch: 1.2.0 (5).

## Headline numbers

Release, 2026-10-15, commit `2958120`, KPI file: import 0.358 s, open 0.580 s, export 2.282 s, fingerprint 3.922 s, June scroll worst 0.146 s, one edit 0.004 s. Scalar answer check: 48191 formulas, 11894 mismatches. Ground-truth answer check: not built.

## Progress log

- 2026-10-15 — W1: agent rulebook, status, gaps, and function parity. Gate not built yet.
- 2026-10-15 — `2958120`: sheet switch returns before cross-sheet calc; save returns before the export write finishes. Viewport scroll and Find focus stay.
- 2026-10-11 — Performance rules and the older KPI baseline recorded on `main`.
