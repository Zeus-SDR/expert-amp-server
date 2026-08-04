#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=package-common.sh
source "$SCRIPT_DIR/package-common.sh"

verify_package
require_root

if [[ ! -x "$BINARY_PATH" || ! -f "$UNIT_PATH" ]]; then
  echo "No complete installation was found; use install.sh for the first install." >&2
  exit 1
fi

BACKUP_DIR="$(mktemp -d /tmp/expert-amp-server-zeus-upgrade.XXXXXX)"
trap 'rm -rf -- "$BACKUP_DIR"' EXIT
install -m 0755 "$BINARY_PATH" "$BACKUP_DIR/expert-amp-server"
install -m 0644 "$UNIT_PATH" "$BACKUP_DIR/expert-amp-server.service"

was_active=false
if systemctl is-active --quiet "$SERVICE_NAME"; then
  was_active=true
  systemctl stop "$SERVICE_NAME"
fi

rollback() {
  echo "Upgrade failed; restoring the previous binary and service unit." >&2
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  install -o root -g root -m 0755 "$BACKUP_DIR/expert-amp-server" "$BINARY_PATH"
  install -o root -g root -m 0644 "$BACKUP_DIR/expert-amp-server.service" "$UNIT_PATH"
  systemctl daemon-reload
  if [[ "$was_active" == true ]]; then
    systemctl start "$SERVICE_NAME" || true
  fi
}

if ! install_payload; then
  rollback
  exit 1
fi

if ! systemctl start "$SERVICE_NAME" || ! verify_service_ready; then
  rollback
  exit 1
fi
if [[ "$was_active" != true ]]; then
  systemctl stop "$SERVICE_NAME"
fi

echo "Zeus Expert Amp Server upgraded; the existing configuration was preserved."
