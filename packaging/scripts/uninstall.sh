#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=package-common.sh
source "$SCRIPT_DIR/package-common.sh"

purge=false
if [[ "${1:-}" == "--purge" ]]; then
  purge=true
elif [[ $# -ne 0 ]]; then
  echo "usage: sudo ./uninstall.sh [--purge]" >&2
  exit 2
fi

verify_package
require_root

if [[ ! -e "$BINARY_PATH" && -x "$LEGACY_BINARY_PATH" ]]; then
  echo "A legacy /usr/local/bin installation was found; migrate or remove it explicitly instead of using the Zeus uninstaller." >&2
  exit 1
fi

systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true
rm -f -- "$UNIT_PATH" "$BINARY_PATH"
rmdir "$INSTALL_DIR" 2>/dev/null || true
systemctl daemon-reload
systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true

if [[ "$purge" == true ]]; then
  rm -rf -- "$STATE_DIR"
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    userdel "$SERVICE_USER"
  fi
  if getent group "$SERVICE_GROUP" >/dev/null; then
    groupdel "$SERVICE_GROUP" 2>/dev/null || true
  fi
  echo "Zeus Expert Amp Server and its configuration were removed."
else
  echo "Zeus Expert Amp Server was removed; configuration remains at $CONFIG_PATH."
  echo "Run sudo ./uninstall.sh --purge only if you also want to delete that configuration."
fi
