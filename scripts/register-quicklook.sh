#!/bin/bash
# Register Spark Grid's Finder Quick Look extension and refresh generators.
# Run after installing/building Spark Grid (Debug or Release).
set -euo pipefail

BUNDLE_ID="com.sparkbysam.SparkGrid.QuickLook"
APP_NAME="Spark Grid"

resolve_app() {
  if [[ -n "${1:-}" && -d "$1" ]]; then
    echo "$1"
    return
  fi
  if [[ -d "/Applications/${APP_NAME}.app" ]]; then
    echo "/Applications/${APP_NAME}.app"
    return
  fi
  # Prefer the frontmost installed copy Launch Services knows about.
  local ls_path
  ls_path="$(mdfind "kMDItemCFBundleIdentifier == 'com.sparkbysam.SparkGrid'" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$ls_path" && -d "$ls_path" ]]; then
    echo "$ls_path"
    return
  fi
  return 1
}

APP_PATH="$(resolve_app "${1:-}" || true)"
if [[ -z "${APP_PATH}" ]]; then
  echo "error: couldn't find ${APP_NAME}.app"
  echo "usage: $0 [/path/to/Spark Grid.app]"
  echo "Build & run from Xcode, or copy the app to /Applications, then re-run."
  exit 1
fi

APPEX="${APP_PATH}/Contents/PlugIns/Spark Grid Quick Look.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "error: Quick Look appex missing at:"
  echo "  $APPEX"
  echo "Rebuild the Spark Grid scheme so the extension is embedded."
  exit 1
fi

echo "Using app:  $APP_PATH"
echo "Using appex: $APPEX"

# Launch once so LaunchServices / PlugInKit discover the appex.
open -a "$APP_PATH" || true
sleep 1

pluginkit -a "$APPEX" || true
pluginkit -e use -i "$BUNDLE_ID" || true

killall quicklookd QuickLookUIService 2>/dev/null || true
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

echo
echo "Registered extensions matching Spark Grid:"
pluginkit -mAvvv -p com.apple.quicklook.preview 2>/dev/null | grep -i -A2 -B2 "SparkGrid\|Spark Grid" || {
  echo "(no Spark Grid preview plugin listed yet — try launching the app once more)"
}

echo
echo "Done. In Finder, select a .csv or .xlsx and press Space."
echo "You should see the Spark Grid toolbar (Save / Open in Spark Grid)."
