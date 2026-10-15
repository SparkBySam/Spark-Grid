#!/bin/bash
# Private KPI answer check. Skip unless SPARK_GRID_CORPUS is set on a local machine.
# Hosted CI (CI or SPARK_GRID_CI) always skips. Exit 10 is a skip, not a pass of the check.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/Packages/SparkGridCore/Package.swift"

if [[ -n "${CI:-}" || -n "${SPARK_GRID_CI:-}" ]]; then
  echo "private corpus is not used on hosted CI"
  exit 10
fi

if [[ -z "${SPARK_GRID_CORPUS:-}" ]]; then
  echo "SPARK_GRID_CORPUS is not set"
  exit 10
fi

if ! grep -q 'name: "AnswerCheck"' "$manifest"; then
  echo "check-kpi: SPARK_GRID_CORPUS is set but AnswerCheck is not built (W5)." >&2
  exit 1
fi

cd "$root/Packages/SparkGridCore"
swift test --filter CorpusAnswerCheck
