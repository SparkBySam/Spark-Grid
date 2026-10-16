#!/bin/bash
# Commit gate. Stages run in order and stop at the first failure.
# Exit 10 from a stage is a documented skip, not a weakened check.
# A local KPI skip is a failure. Hosted CI may still skip that stage.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
ci_app_dd="/tmp/spark-grid-ci-app"
ci_ql_dd="/tmp/spark-grid-ci-ql"
cleanup_ci_builds() {
  rm -rf "$ci_app_dd" "$ci_ql_dd"
}
trap cleanup_ci_builds EXIT
started="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
elapsed() {
  perl -MTime::HiRes=time -e 'printf "%.1f", time - $ARGV[0]' "$started"
}

hosted_ci() {
  [[ -n "${CI:-}" || -n "${SPARK_GRID_CI:-}" ]]
}

# Directory that contains every file named in corpus/manifest.json.
# Prints nothing when this machine does not have the private corpus.
find_corpus_dir() {
  local manifest="$1"
  local name dir ok
  local -a names
  [[ -f "$manifest" ]] || return 0
  names=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && names+=("$name")
  done < <(python3 -c 'import json,sys; print("\n".join(i["name"] for i in json.load(open(sys.argv[1]))["files"]))' "$manifest")
  [[ ${#names[@]} -gt 0 ]] || return 0
  for dir in "$HOME/Downloads" "$HOME/SparkGridCorpus"; do
    [[ -d "$dir" ]] || continue
    ok=1
    for name in "${names[@]}"; do
      if [[ ! -f "$dir/$name" ]]; then
        ok=0
        break
      fi
    done
    if [[ "$ok" -eq 1 ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
}

run_stage() {
  local name="$1"
  shift
  local log code reason
  log="$(mktemp "${TMPDIR:-/tmp}/spark-grid-ci.XXXXXX")"
  set +e
  "$@" >"$log" 2>&1
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "$name: PASS"
  elif [[ "$code" -eq 10 ]]; then
    if [[ "$name" == "kpi" ]] && ! hosted_ci; then
      cat "$log" >&2
      echo "$name: FAIL"
      echo "FAIL ($(elapsed)s)"
      rm -f "$log"
      exit 1
    fi
    reason="$(tr '\n' ' ' <"$log" | sed 's/[[:space:]]*$//')"
    echo "$name: SKIP ${reason}"
  else
    cat "$log" >&2
    echo "$name: FAIL"
    echo "FAIL ($(elapsed)s)"
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}

privacy_and_assets() {
  set +e
  "$root/scripts/check-privacy.sh"
  local privacy=$?
  "$root/scripts/check-assets.sh"
  local assets=$?
  set -e
  [[ "$privacy" -eq 0 && "$assets" -eq 0 ]]
}

kpi_stage() {
  if ! hosted_ci && [[ -z "${SPARK_GRID_CORPUS:-}" ]]; then
    local dir
    dir="$(find_corpus_dir "$root/corpus/manifest.json")"
    if [[ -n "$dir" ]]; then
      export SPARK_GRID_CORPUS="$dir"
    fi
  fi
  "$root/scripts/check-kpi.sh"
}

run_stage lint "$root/scripts/lint.sh"
run_stage format "$root/scripts/check-format.sh"
run_stage package "$root/scripts/check-package.sh" release
run_stage xcodebuild "$root/scripts/check-xcodebuild.sh"
run_stage layers "$root/scripts/check-layers.sh"
run_stage privacy-assets privacy_and_assets
run_stage ledger "$root/scripts/check-ledger.sh"
run_stage kpi kpi_stage
run_stage fuzz "$root/scripts/check-fuzz.sh"

echo "PASS ($(elapsed)s)"
