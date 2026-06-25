#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Connectum"
BUNDLE_ID="com.connectum.app"
PROJECT_REL="apps/Connectum/Connectum.xcodeproj"
SCHEME="Connectum"
CONFIGURATION="${CONNECTUM_CONFIGURATION:-Release}"
INSTALL_APP="/Applications/${APP_NAME}.app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT_REL"
DERIVED_DATA="$ROOT_DIR/.build/xcode"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/${APP_NAME}.app"

usage() {
  echo "usage: $0 [run|--install|--verify|--debug|--logs|--telemetry|--install-verify]" >&2
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

generate_project() {
  if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR/apps/Connectum" && xcodegen generate >/dev/null)
  fi
}

build_app() {
  generate_project
  xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'platform=macOS'
}

install_app() {
  local temp_app
  temp_app="/Applications/.${APP_NAME}.app.tmp"
  rm -rf "$temp_app"
  ditto "$BUILT_APP" "$temp_app"
  rm -rf "$INSTALL_APP"
  mv "$temp_app" "$INSTALL_APP"
}

open_built_app() {
  /usr/bin/open -n "$BUILT_APP"
}

open_installed_app() {
  /usr/bin/open -n "$INSTALL_APP"
}

stream_process_logs() {
  /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
}

stream_telemetry_logs() {
  /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
}

verify_process() {
  sleep 2
  pgrep -x "$APP_NAME" >/dev/null
}

case "$MODE" in
  run)
    stop_app
    build_app
    open_built_app
    ;;
  --install|install)
    stop_app
    build_app
    install_app
    open_installed_app
    ;;
  --verify|verify)
    stop_app
    build_app
    open_built_app
    verify_process
    ;;
  --debug|debug)
    stop_app
    build_app
    lldb -- "$BUILT_APP/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    stop_app
    build_app
    open_built_app
    stream_process_logs
    ;;
  --telemetry|telemetry)
    stop_app
    build_app
    open_built_app
    stream_telemetry_logs
    ;;
  --install-verify|install-verify)
    stop_app
    build_app
    install_app
    open_installed_app
    verify_process
    ;;
  *)
    usage
    exit 2
    ;;
esac
