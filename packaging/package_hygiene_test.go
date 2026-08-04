package packaging

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repositoryFile(t *testing.T, path ...string) string {
	t.Helper()
	parts := append([]string{".."}, path...)
	body, err := os.ReadFile(filepath.Join(parts...))
	if err != nil {
		t.Fatalf("read %s: %v", filepath.Join(parts...), err)
	}
	return string(body)
}

func requireFragments(t *testing.T, body string, fragments ...string) {
	t.Helper()
	for _, fragment := range fragments {
		if !strings.Contains(body, fragment) {
			t.Errorf("missing required distribution fragment %q", fragment)
		}
	}
}

func TestReleaseBuilderProducesOnlyStaticSupportedLinuxBundles(t *testing.T) {
	body := repositoryFile(t, "packaging", "scripts", "build-release.sh")
	requireFragments(t, body,
		`"arm64:arm64:"`,
		`"armv7:arm:7"`,
		`"amd64:amd64:"`,
		"CGO_ENABLED=0 GOOS=linux",
		"-extldflags=-static",
		"-buildvcs=false",
		"-trimpath",
		"main.Distribution=$DISTRIBUTION",
		"main.UpstreamVersion=$UPSTREAM_VERSION",
		"main.UpstreamCommit=$UPSTREAM_COMMIT",
		"MANIFEST.SHA256",
		"SHA256SUMS",
		`tar --sort=name --mtime="@$SOURCE_DATE_EPOCH"`,
	)
	for _, unsupported := range []string{"darwin/", "windows/", "linux/386"} {
		if strings.Contains(body, unsupported) {
			t.Errorf("release builder unexpectedly contains unsupported target %q", unsupported)
		}
	}
}

func TestSystemdUnitIsHardenedWithoutHidingUSBSerialDevices(t *testing.T) {
	body := repositoryFile(t, "packaging", "systemd", "expert-amp-server.service")
	requireFragments(t, body,
		"User=expert-amp",
		"SupplementaryGroups=dialout",
		"NoNewPrivileges=true",
		"ProtectSystem=strict",
		"ProtectHome=true",
		"ProtectKernelTunables=true",
		"ProtectKernelModules=true",
		"ProtectControlGroups=true",
		"RestrictSUIDSGID=true",
		"LockPersonality=true",
		"MemoryDenyWriteExecute=true",
		"CapabilityBoundingSet=",
		"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6",
		"ReadWritePaths=/var/lib/expert-amp-server",
	)
	for _, unsafe := range []string{"User=root", "PrivateDevices=true", "ProtectSystem=full"} {
		if strings.Contains(body, unsafe) {
			t.Errorf("service contains unsafe or serial-breaking setting %q", unsafe)
		}
	}
}

func TestLifecycleScriptsVerifyBundleAndAvoidRemoteShellExecution(t *testing.T) {
	common := repositoryFile(t, "packaging", "scripts", "package-common.sh")
	requireFragments(t, common,
		"sha256sum --check --strict MANIFEST.SHA256",
		"Run this operator script with sudo; do not pipe it into a shell.",
		`if [[ ! -e "$CONFIG_PATH" ]]`,
		"install -o root -g root -m 0755",
		"port_8088_in_use",
		"verify_service_ready",
		`VERIFY_PORT="${EXPERT_AMP_VERIFY_PORT:-8088}"`,
		`EXPECTED_VERSION="$(tr -d '\r\n' < "$PACKAGE_DIR/VERSION")"`,
		`/dev/tcp/127.0.0.1/$VERIFY_PORT`,
		"timeout 2",
		"/healthz",
		"/api/v1/version",
		`"distribution":"zeus"`,
		`\"version\":\"$EXPECTED_VERSION\"`,
		`LEGACY_BINARY_PATH="/usr/local/bin/expert-amp-server"`,
		"ensure_service_account || return 1",
		"systemctl daemon-reload || return 1",
	)

	for _, name := range []string{"install.sh", "upgrade.sh", "uninstall.sh"} {
		body := repositoryFile(t, "packaging", "scripts", name)
		requireFragments(t, body, "set -euo pipefail", "source \"$SCRIPT_DIR/package-common.sh\"", "verify_package", "require_root")
		for _, forbidden := range []string{"curl ", "wget ", "| sh", "| bash", "eval "} {
			if strings.Contains(body, forbidden) {
				t.Errorf("%s contains forbidden remote-execution pattern %q", name, forbidden)
			}
		}
	}

	uninstall := repositoryFile(t, "packaging", "scripts", "uninstall.sh")
	requireFragments(t, uninstall, "--purge", "configuration remains", `rm -rf -- "$STATE_DIR"`)
	upgrade := repositoryFile(t, "packaging", "scripts", "upgrade.sh")
	requireFragments(t, upgrade, "rollback", "restoring the previous binary and service unit", "existing configuration was preserved")
	install := repositoryFile(t, "packaging", "scripts", "install.sh")
	requireFragments(t, install,
		"--migrate-existing",
		"migrate_legacy_installation",
		`cp -a -- "$LEGACY_BINARY_PATH"`,
		`cp -a -- "$CONFIG_PATH"`,
		"systemctl stop",
		"systemctl enable --now",
		"verify_service_ready",
		"Migration failed; restoring the legacy binary, unit, and configuration.",
		`rm -f -- "$LEGACY_BINARY_PATH"`,
		"migration-backup-",
		"Port 8088 is already listening without a recognized systemd installation.",
		"it will not be killed or overwritten automatically",
		"rollback_fresh_install",
		"Install failed; removing the incomplete service and binary.",
	)
}

func TestFreshInstallConfigDoesNotGuessSerialDevice(t *testing.T) {
	body := repositoryFile(t, "packaging", "config", "config.example.json")
	var config struct {
		SerialPort    string `json:"serialPort"`
		ListenAddress string `json:"listenAddress"`
	}
	if err := json.Unmarshal([]byte(body), &config); err != nil {
		t.Fatalf("decode config.example.json: %v", err)
	}
	if config.SerialPort != "" {
		t.Fatalf("SerialPort = %q, want blank first-run setup", config.SerialPort)
	}
	if config.ListenAddress != ":8088" {
		t.Fatalf("ListenAddress = %q, want trusted-LAN :8088 default", config.ListenAddress)
	}
}

func TestOfficialReleaseWorkflowIsTagDrivenAndUsesPinnedGo(t *testing.T) {
	body := repositoryFile(t, ".github", "workflows", "release.yml")
	requireFragments(t, body,
		`tags:`,
		`- "zeus-v*"`,
		"contents: write",
		"actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4",
		"actions/setup-go@924ae3a1cded613372ab5595356fb5720e22ba16 # v6",
		`go-version: "1.26.5"`,
		"go test ./...",
		"bash packaging/scripts/build-release.sh",
		"bash packaging/scripts/package-common_test.sh",
		"sha256sum --check --strict SHA256SUMS",
		"gh release create",
		"--verify-tag",
	)
}

func TestBundleCarriesAttributionAndG2OperatorGuide(t *testing.T) {
	build := repositoryFile(t, "packaging", "scripts", "build-release.sh")
	for _, name := range []string{"README_G2.md", "PROVENANCE.md", "THIRD_PARTY_LICENSES.txt", "THIRD_PARTY_NOTICES.md", "LICENSE"} {
		if !strings.Contains(build, name) {
			t.Errorf("release bundle does not include %s", name)
		}
	}
	provenance := repositoryFile(t, "PROVENANCE.md")
	requireFragments(t, provenance,
		"FtlC-ian/expert-amp-server",
		"v0.4.5",
		"373fc5b5b9e851ae14f89c1c40c4e64816a51284",
		"amplifier protocol, serial transport, fan policy, menu navigation, control authorization, and safety behavior",
	)
}

func TestBinaryDistributionReproducesDependencyLicenseNotices(t *testing.T) {
	body := repositoryFile(t, "THIRD_PARTY_LICENSES.txt")
	for _, notice := range []string{
		"Copyright 2009 The Go Authors.",
		"Copyright (c) 2013 The Gorilla WebSocket Authors. All rights reserved.",
		"Copyright (c) 2014-2024, Cristian Maglie.",
		"Copyright (c) 2014 Guillaume J. Charmes",
		"Copyright (c) 2009 The Go Authors. All rights reserved.",
		"Redistributions in binary form must reproduce the above copyright notice",
		"The MIT License (MIT)",
	} {
		if !strings.Contains(body, notice) {
			t.Errorf("third-party license bundle missing verbatim notice text %q", notice)
		}
	}
}

func TestPinnedDependencyVersionsMatchBundledLicenseSources(t *testing.T) {
	goSum := repositoryFile(t, "go.sum")
	for _, version := range []string{
		"github.com/gorilla/websocket v1.5.3 ",
		"go.bug.st/serial v1.6.4 ",
		"github.com/creack/goselect v0.1.2 ",
		"golang.org/x/sys v0.19.0 ",
	} {
		if !strings.Contains(goSum, version) {
			t.Errorf("go.sum no longer matches bundled license source %q", version)
		}
	}
}

func TestUpstreamMITLicenseRemainsVerbatim(t *testing.T) {
	body := strings.ReplaceAll(repositoryFile(t, "LICENSE"), "\r\n", "\n")
	sum := sha256.Sum256([]byte(body))
	if got, want := fmt.Sprintf("%x", sum), "3c8cf483c5f5a2a972fb488a3f743d1ce9bdd9e40d19751220a42788e880619c"; got != want {
		t.Fatalf("upstream LICENSE changed: SHA-256 = %s, want %s", got, want)
	}
}

func TestOpenAPIDocumentsDistributionVersionContract(t *testing.T) {
	body := repositoryFile(t, "internal", "apidocs", "openapi.json")
	for _, field := range []string{`"distribution"`, `"upstreamVersion"`, `"upstreamCommit"`} {
		if !strings.Contains(body, field) {
			t.Errorf("OpenAPI version contract missing %s", field)
		}
	}
}
