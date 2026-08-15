#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=package-common.sh
source "$SCRIPT_DIR/package-common.sh"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/expert-amp-server-package-test.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT

PACKAGE_DIR="$fixture/package"
INSTALL_DIR="$fixture/install"
BINARY_PATH="$INSTALL_DIR/expert-amp-server"
STATE_DIR="$fixture/state"
CONFIG_PATH="$STATE_DIR/config.json"
UNIT_PATH="$fixture/expert-amp-server.service"
mkdir -p "$PACKAGE_DIR/bin" "$PACKAGE_DIR/config" "$PACKAGE_DIR/systemd"
touch "$PACKAGE_DIR/bin/expert-amp-server"
touch "$PACKAGE_DIR/config/config.example.json"
touch "$PACKAGE_DIR/systemd/expert-amp-server.service"

# Account creation is part of the same conditional call chain and must also
# propagate an intermediate groupadd failure explicitly.
test_account_failfast() {
  getent() { return 1; }
  groupadd() { return 29; }
  if ensure_service_account; then
    echo "ensure_service_account ignored an intermediate groupadd failure" >&2
    return 1
  fi
}
test_account_failfast

# Recreate the caller's `if ! install_payload` context, which disables Bash's
# automatic errexit behavior inside the function. The explicit return checks
# must stop before daemon-reload after this intermediate config-copy failure.
ensure_service_account() { return 0; }
daemon_reload_called=false
systemctl() {
  daemon_reload_called=true
  return 0
}
install() {
  local destination="${!#}"
  if [[ "$destination" == "$CONFIG_PATH" ]]; then
    return 23
  fi
  if [[ " $* " == *" -d "* ]]; then
    mkdir -p -- "$destination"
  else
    mkdir -p -- "$(dirname "$destination")"
    touch -- "$destination"
  fi
}

if install_payload; then
  echo "install_payload ignored an intermediate config installation failure" >&2
  exit 1
fi
if [[ "$daemon_reload_called" == true ]]; then
  echo "install_payload continued to daemon-reload after an intermediate failure" >&2
  exit 1
fi

echo "package-common fail-fast regression checks passed"
