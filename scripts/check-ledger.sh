#!/bin/bash
# Ledger ground truth. The AnswerCheck target is W5 and is not in the package yet.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/Packages/SparkGridCore/Package.swift"

if ! grep -q 'name: "AnswerCheck"' "$manifest"; then
  echo "check-ledger: AnswerCheck is not built (W5). The ledger saved-result check cannot run." >&2
  exit 1
fi

cd "$root/Packages/SparkGridCore"
swift test --filter AnswerCheck
