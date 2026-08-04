#!/usr/bin/env bash

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/lib/expert-amp-server"
BINARY_PATH="$INSTALL_DIR/expert-amp-server"
STATE_DIR="/var/lib/expert-amp-server"
CONFIG_PATH="$STATE_DIR/config.json"
UNIT_PATH="/etc/systemd/system/expert-amp-server.service"
SERVICE_NAME="expert-amp-server.service"
SERVICE_USER="expert-amp"
SERVICE_GROUP="expert-amp"
LEGACY_BINARY_PATH="/usr/local/bin/expert-amp-server"
VERIFY_PORT="${EXPERT_AMP_VERIFY_PORT:-8088}"
EXPECTED_VERSION=""
if [[ -f "$PACKAGE_DIR/VERSION" ]]; then
  EXPECTED_VERSION="$(tr -d '\r\n' < "$PACKAGE_DIR/VERSION")"
fi

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run this operator script with sudo; do not pipe it into a shell." >&2
    exit 1
  fi
}

verify_package() {
  command -v sha256sum >/dev/null 2>&1 || {
    echo "sha256sum is required to verify this release bundle." >&2
    exit 1
  }
  [[ -f "$PACKAGE_DIR/MANIFEST.SHA256" ]] || {
    echo "MANIFEST.SHA256 is missing; refusing to install an incomplete bundle." >&2
    exit 1
  }
  echo "Verifying release bundle checksums..."
  (cd "$PACKAGE_DIR" && sha256sum --check --strict MANIFEST.SHA256)
}

port_8088_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 'sport = :8088' 2>/dev/null | grep -q .
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:8088 -sTCP:LISTEN >/dev/null 2>&1
    return
  fi
  return 1
}

local_http_get() {
  local path="$1" response=""
  if ! exec 3<>"/dev/tcp/127.0.0.1/$VERIFY_PORT"; then
    return 1
  fi
  if ! printf 'GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n' "$path" >&3; then
    exec 3<&- 3>&-
    return 1
  fi
  if ! response="$(timeout 2 cat <&3)"; then
    exec 3<&- 3>&-
    return 1
  fi
  exec 3<&- 3>&-
  printf '%s' "$response"
}

verify_service_ready() {
  if [[ ! "$VERIFY_PORT" =~ ^[0-9]+$ ]] || ((VERIFY_PORT < 1 || VERIFY_PORT > 65535)); then
    echo "EXPERT_AMP_VERIFY_PORT must be a TCP port number from 1 through 65535." >&2
    return 1
  fi
  command -v timeout >/dev/null 2>&1 || {
    echo "GNU timeout is required for bounded local service verification." >&2
    return 1
  }
  if [[ -z "$EXPECTED_VERSION" || "$EXPECTED_VERSION" == *'"'* ]]; then
    echo "The release bundle VERSION is missing or invalid; service identity cannot be verified." >&2
    return 1
  fi
  local attempt health version
  for attempt in {1..10}; do
    if systemctl is-active --quiet "$SERVICE_NAME"; then
      health="$(local_http_get /healthz 2>/dev/null || true)"
      version="$(local_http_get /api/v1/version 2>/dev/null || true)"
      if [[ "$health" == *" 200 "* && "$health" == *$'\r\n\r\nok'* &&
            "$version" == *" 200 "* &&
            "$version" == *'"distribution":"zeus"'* &&
            "$version" == *"\"version\":\"$EXPECTED_VERSION\""* ]]; then
        return 0
      fi
    fi
    sleep 1
  done
  echo "The service did not pass bounded localhost /healthz and Zeus /api/v1/version verification." >&2
  journalctl -u "$SERVICE_NAME" -n 20 --no-pager >&2 || true
  return 1
}

ensure_service_account() {
  if ! getent group "$SERVICE_GROUP" >/dev/null; then
    groupadd --system "$SERVICE_GROUP" || return 1
  fi
  if ! getent group dialout >/dev/null; then
    groupadd --system dialout || return 1
  fi
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --gid "$SERVICE_GROUP" --groups dialout \
      --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$SERVICE_USER" || return 1
  else
    usermod --append --groups dialout "$SERVICE_USER" || return 1
  fi
}

install_payload() {
  # Callers deliberately use this function in a conditional so they can run
  # transactional rollback. Bash suppresses errexit in that context; every
  # mutating command therefore returns explicitly on failure.
  ensure_service_account || return 1
  install -d -o root -g root -m 0755 "$INSTALL_DIR" || return 1
  install -o root -g root -m 0755 "$PACKAGE_DIR/bin/expert-amp-server" "$BINARY_PATH" || return 1
  install -d -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0750 "$STATE_DIR" || return 1
  if [[ ! -e "$CONFIG_PATH" ]]; then
    install -o "$SERVICE_USER" -g "$SERVICE_GROUP" -m 0600 \
      "$PACKAGE_DIR/config/config.example.json" "$CONFIG_PATH" || return 1
    echo "Created $CONFIG_PATH; configure the stable /dev/serial/by-id path in the web Settings page."
  fi
  install -o root -g root -m 0644 \
    "$PACKAGE_DIR/systemd/expert-amp-server.service" "$UNIT_PATH" || return 1
  systemctl daemon-reload || return 1
}
