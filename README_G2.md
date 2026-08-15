# Zeus Expert Amp Server on ANAN G2

This is the operator guide for the official Zeus SDR Linux distribution of Expert Amp Server. The primary package is static Linux ARM64 for the ANAN G2/G2 Ultra internal Raspberry Pi Compute Module. ARMv7 and AMD64 packages are released from the same source for compatible station hosts.

The server exposes state-changing amplifier controls without built-in authentication. Install it only on a trusted station LAN. Do not forward port 8088 to the public internet.

## Hardware connection

Connect the SPE amplifier's built-in USB Type-B control port to the G2 Linux host. Do not use one of the amplifier's separate CAT radio ports. After installation, choose a stable path under `/dev/serial/by-id/` in the server Settings page; `/dev/ttyUSB0` can change when devices are reconnected.

The `expert-amp` service account is added to `dialout` for serial access. The service intentionally retains access to host USB serial devices while its filesystem access is restricted to `/var/lib/expert-amp-server`.

## Select the release bundle

Open the official [Zeus Expert Amp Server releases](https://github.com/Zeus-SDR/expert-amp-server/releases) page and select a `zeus-v...` release.

Use this asset for a normal 64-bit G2:

```text
expert-amp-server-zeus_linux_arm64.tar.gz
```

Use `linux_armv7` only when `uname -m` reports `armv7l`. Use `linux_amd64` for an x86-64 Linux station computer.

## Checksum, unpack, and install

Download both `SHA256SUMS` and the selected archive from the same tagged release. Pin the tag shown on the release page instead of using an unreviewed moving URL:

```bash
TAG=zeus-vX.Y.Z
ASSET=expert-amp-server-zeus_linux_arm64.tar.gz
BASE=https://github.com/Zeus-SDR/expert-amp-server/releases/download/$TAG
curl --fail --location --remote-name "$BASE/SHA256SUMS"
curl --fail --location --remote-name "$BASE/$ASSET"
grep "  $ASSET$" SHA256SUMS | sha256sum --check --strict -
tar -xzf "$ASSET"
cd expert-amp-server-zeus
sudo ./install.sh
```

Replace `zeus-vX.Y.Z` with the exact published tag. Never pipe a downloaded installer into a shell. The outer checksum verifies the archive before extraction; `install.sh` then verifies every packaged file against `MANIFEST.SHA256` before making system changes.

The installer:

- creates the locked-down `expert-amp` service account and adds serial access through `dialout`;
- installs the binary under `/usr/local/lib/expert-amp-server`;
- creates `/var/lib/expert-amp-server/config.json` only when it does not already exist;
- installs and starts the hardened `expert-amp-server.service` unit.

Open `http://G2-IP-ADDRESS:8088/`, go to Settings, select the amplifier serial path, and save. The initial blank serial path intentionally starts in setup mode instead of guessing a USB device.

### Migrate an existing upstream G2 service

Earlier G2 installations commonly use `/usr/local/bin/expert-amp-server` with the same `/etc/systemd/system/expert-amp-server.service` name and `/var/lib/expert-amp-server/config.json`. Do not run the fresh installer or copy the Zeus binary over that deployment. From a newly checksum-verified Zeus bundle, run:

```bash
sudo ./install.sh --migrate-existing
```

The migration accepts only that recognized legacy systemd layout. It records whether the old service was enabled/running, backs up the old binary, unit, and configuration, stops the old unit, installs the Zeus payload under `/usr/local/lib`, and starts the replacement using the same service name. Success requires bounded localhost HTTP 200 checks of both `/healthz` and `/api/v1/version`, with the version response identifying `distribution` as `zeus` and matching the exact version recorded in the verified bundle. Verification uses Bash `/dev/tcp` plus the standard GNU coreutils `timeout` command, so it does not add a curl dependency. The default verification port is 8088; for an existing config with another loopback-reachable port, run the script through `sudo env EXPERT_AMP_VERIFY_PORT=PORT ./install.sh --migrate-existing` (or `upgrade.sh`). Only after those checks pass does it remove the legacy binary. The root-only backup remains under `/var/lib/expert-amp-server/migration-backup-*`.

If installation or startup fails, the transaction restores the old binary, unit, config, enablement, and running state. If the old server was launched manually, uses a nonstandard unit/config path, or merely occupies port 8088, the script refuses to guess or kill it; stop and account for that deployment explicitly before installing.

Verify process and distribution identity:

```bash
curl http://127.0.0.1:8088/healthz
curl http://127.0.0.1:8088/api/v1/version
sudo systemctl status expert-amp-server
sudo journalctl -u expert-amp-server -f
```

`/healthz` proves only that the process is running. Confirm `/api/v1/status` reports recent serial contact and the expected amplifier before using controls.

## Upgrade

Download the new architecture-matched archive and its `SHA256SUMS`, verify and unpack them exactly as above, then run:

```bash
cd expert-amp-server-zeus
sudo ./upgrade.sh
```

The upgrade preserves `/var/lib/expert-amp-server/config.json`. It starts the new binary long enough to run the same bounded health/version identity checks, then returns it to stopped state when the old service was stopped. If startup or either check fails, the script restores the previous binary and unit.

## Uninstall

Run the checksum-verified uninstall script from a verified release bundle:

```bash
sudo ./uninstall.sh
```

That removes the service and binary but deliberately preserves the station configuration. To delete the configuration and service account too:

```bash
sudo ./uninstall.sh --purge
```

The purge is irreversible; copy `/var/lib/expert-amp-server/config.json` first if it may be needed again.

## G2 notes

- ARM64 is the primary release target. Confirm with `uname -m` before installing.
- The service listens on `:8088` for the trusted station LAN by default.
- The service needs no root privileges and receives no Linux capabilities.
- Do not enable automatic fan or temperature actions until the amplifier temperature unit and model behavior have been verified for the station. Distribution packaging does not change upstream control safeguards or defaults.
- The web UI/API restart command exits cleanly; `Restart=always` lets systemd bring the service back.

For protocol, control, and amplifier-specific details, continue with the main [README](README.md) and upstream-derived documentation under [docs](docs/README.md).
