#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --always --dirty)}"
COMMIT="${COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" show -s --format=%ct HEAD)}"
BUILD_DATE="${BUILD_DATE:-$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%dT%H:%M:%SZ)}"
CHANNEL="${CHANNEL:-dev}"
DISTRIBUTION="${DISTRIBUTION:-zeus}"
UPSTREAM_VERSION="${UPSTREAM_VERSION:-v0.4.5}"
UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-373fc5b5b9e851ae14f89c1c40c4e64816a51284}"
TARGETS=(
  "arm64:arm64:"
  "armv7:arm:7"
  "amd64:amd64:"
)

mkdir -p "$OUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/expert-amp-server-zeus-release.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT

checksum_files() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}

ldflags="-s -w -extldflags=-static"
ldflags+=" -X main.Version=$VERSION"
ldflags+=" -X main.Commit=$COMMIT"
ldflags+=" -X main.BuildDate=$BUILD_DATE"
ldflags+=" -X main.Channel=$CHANNEL"
ldflags+=" -X main.Distribution=$DISTRIBUTION"
ldflags+=" -X main.UpstreamVersion=$UPSTREAM_VERSION"
ldflags+=" -X main.UpstreamCommit=$UPSTREAM_COMMIT"

archives=()
for target in "${TARGETS[@]}"; do
  IFS=: read -r label goarch goarm <<<"$target"
  bundle="$WORK_DIR/$label/expert-amp-server-zeus"
  mkdir -p "$bundle/bin" "$bundle/config" "$bundle/systemd"

  echo "building static linux/$label"
  if [[ -n "$goarm" ]]; then
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" GOARM="$goarm" \
      go build -buildvcs=false -trimpath -tags netgo,osusergo -ldflags "$ldflags" \
      -o "$bundle/bin/expert-amp-server" "$ROOT/cmd/server"
  else
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" \
      go build -buildvcs=false -trimpath -tags netgo,osusergo -ldflags "$ldflags" \
      -o "$bundle/bin/expert-amp-server" "$ROOT/cmd/server"
  fi

  install -m 0644 "$ROOT/packaging/config/config.example.json" "$bundle/config/config.example.json"
  install -m 0644 "$ROOT/packaging/systemd/expert-amp-server.service" "$bundle/systemd/expert-amp-server.service"
  install -m 0755 "$ROOT/packaging/scripts/package-common.sh" "$bundle/package-common.sh"
  install -m 0755 "$ROOT/packaging/scripts/install.sh" "$bundle/install.sh"
  install -m 0755 "$ROOT/packaging/scripts/upgrade.sh" "$bundle/upgrade.sh"
  install -m 0755 "$ROOT/packaging/scripts/uninstall.sh" "$bundle/uninstall.sh"
  install -m 0644 "$ROOT/README_G2.md" "$bundle/README_G2.md"
  install -m 0644 "$ROOT/LICENSE" "$bundle/LICENSE"
  install -m 0644 "$ROOT/THIRD_PARTY_NOTICES.md" "$bundle/THIRD_PARTY_NOTICES.md"
  install -m 0644 "$ROOT/THIRD_PARTY_LICENSES.txt" "$bundle/THIRD_PARTY_LICENSES.txt"
  install -m 0644 "$ROOT/PROVENANCE.md" "$bundle/PROVENANCE.md"
  printf '%s\n' "$VERSION" > "$bundle/VERSION"

  (
    cd "$bundle"
    checksum_files \
      VERSION LICENSE PROVENANCE.md README_G2.md THIRD_PARTY_LICENSES.txt THIRD_PARTY_NOTICES.md \
      bin/expert-amp-server config/config.example.json \
      install.sh package-common.sh uninstall.sh upgrade.sh \
      systemd/expert-amp-server.service > MANIFEST.SHA256
  )

  archive_name="expert-amp-server-zeus_linux_${label}.tar.gz"
  archive="$OUT_DIR/$archive_name"
  tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
    -czf "$archive" -C "$WORK_DIR/$label" expert-amp-server-zeus
  archives+=("$archive_name")
done

(
  cd "$OUT_DIR"
  checksum_files "${archives[@]}" > SHA256SUMS
)

echo "Zeus release bundles written to $OUT_DIR"
