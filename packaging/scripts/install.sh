#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=package-common.sh
source "$SCRIPT_DIR/package-common.sh"

migrate_existing=false
if [[ "${1:-}" == "--migrate-existing" ]]; then
  migrate_existing=true
elif [[ $# -ne 0 ]]; then
  echo "usage: sudo ./install.sh [--migrate-existing]" >&2
  exit 2
fi

verify_package
require_root

fresh_install() {
  if [[ -e "$BINARY_PATH" || -e "$UNIT_PATH" || -e "$LEGACY_BINARY_PATH" ]]; then
    echo "An installation already exists; use upgrade.sh for Zeus or install.sh --migrate-existing for the legacy /usr/local/bin deployment." >&2
    exit 1
  fi
  if port_8088_in_use; then
    echo "Port 8088 is already listening without a recognized systemd installation." >&2
    echo "Stop the manually launched server and account for its config before installing; it will not be killed or overwritten automatically." >&2
    exit 1
  fi

  rollback_fresh_install() {
    echo "Install failed; removing the incomplete service and binary. Any pre-existing config is preserved." >&2
    systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f -- "$UNIT_PATH" "$BINARY_PATH"
    rmdir "$INSTALL_DIR" 2>/dev/null || true
    systemctl daemon-reload
  }
  if ! install_payload ||
     ! systemctl enable --now "$SERVICE_NAME" ||
     ! verify_service_ready; then
    rollback_fresh_install
    exit 1
  fi

  echo "Zeus Expert Amp Server installed."
  echo "Open http://G2-HOSTNAME-OR-IP:8088/ on the trusted station LAN, then configure the amplifier USB serial path."
}

migrate_legacy_installation() {
  if [[ -e "$BINARY_PATH" ]]; then
    echo "The Zeus binary path already exists; use upgrade.sh or inspect the mixed installation manually." >&2
    exit 1
  fi
  if [[ ! -f "$UNIT_PATH" || ! -x "$LEGACY_BINARY_PATH" ]]; then
    if [[ -x "$LEGACY_BINARY_PATH" ]] || port_8088_in_use; then
      echo "A manual or nonstandard legacy server was detected, but no migratable systemd unit was found." >&2
      echo "Stop it and preserve its config manually; this script will not guess its ownership or kill it." >&2
    else
      echo "No legacy /usr/local/bin Expert Amp Server systemd installation was found." >&2
    fi
    exit 1
  fi
  if ! grep -Fq "$LEGACY_BINARY_PATH" "$UNIT_PATH"; then
    echo "The existing unit does not launch $LEGACY_BINARY_PATH; refusing a nonstandard migration." >&2
    exit 1
  fi
  if grep -q -- '-config' "$UNIT_PATH" && ! grep -Fq -- "-config $CONFIG_PATH" "$UNIT_PATH"; then
    echo "The existing unit uses a nonstandard config path; preserve and migrate it manually." >&2
    exit 1
  fi

  rollback_dir="$(mktemp -d /var/tmp/expert-amp-server-zeus-migration.XXXXXX)"
  trap 'rm -rf -- "$rollback_dir"' EXIT
  cp -a -- "$LEGACY_BINARY_PATH" "$rollback_dir/legacy-expert-amp-server"
  cp -a -- "$UNIT_PATH" "$rollback_dir/expert-amp-server.service"
  had_config=false
  if [[ -e "$CONFIG_PATH" ]]; then
    had_config=true
    cp -a -- "$CONFIG_PATH" "$rollback_dir/config.json"
  fi
  was_active=false
  was_enabled=false
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    was_active=true
  fi
  if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    was_enabled=true
  fi

  rollback() {
    echo "Migration failed; restoring the legacy binary, unit, and configuration." >&2
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    rm -f -- "$BINARY_PATH"
    install -o root -g root -m 0755 "$rollback_dir/legacy-expert-amp-server" "$LEGACY_BINARY_PATH"
    install -o root -g root -m 0644 "$rollback_dir/expert-amp-server.service" "$UNIT_PATH"
    if [[ "$had_config" == true ]]; then
      cp -a -- "$rollback_dir/config.json" "$CONFIG_PATH"
    else
      rm -f -- "$CONFIG_PATH"
    fi
    systemctl daemon-reload
    if [[ "$was_enabled" == true ]]; then
      systemctl enable "$SERVICE_NAME" >/dev/null
    else
      systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    fi
    if [[ "$was_active" == true ]]; then
      systemctl start "$SERVICE_NAME" || true
    fi
  }

  systemctl stop "$SERVICE_NAME"
  if ! install_payload; then
    rollback
    exit 1
  fi
  if ! systemctl enable --now "$SERVICE_NAME" || ! verify_service_ready; then
    rollback
    exit 1
  fi

  persistent_backup="$STATE_DIR/migration-backup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  if ! install -d -o root -g root -m 0700 "$persistent_backup" ||
     ! cp -a -- "$rollback_dir/." "$persistent_backup/" ||
     ! rm -f -- "$LEGACY_BINARY_PATH"; then
    rollback
    exit 1
  fi

  echo "Legacy Expert Amp Server migrated to the Zeus distribution."
  echo "The existing config was preserved. A root-only migration backup is at $persistent_backup."
}

if [[ "$migrate_existing" == true ]]; then
  migrate_legacy_installation
else
  fresh_install
fi
