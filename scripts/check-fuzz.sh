#!/bin/bash
# Fuzz smoke. The CommandFuzz target is W5 and is not in the package yet.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$root/Packages/SparkGridCore/Package.swift"

if ! grep -q 'name: "CommandFuzz"' "$manifest"; then
  echo "check-fuzz: CommandFuzz is not built (W5). The fuzz smoke run cannot start." >&2
  exit 1
fi

cd "$root/Packages/SparkGridCore"
swift test --filter CommandFuzz
