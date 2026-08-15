# Distribution provenance

## Upstream base

- Project: [FtlC-ian/expert-amp-server](https://github.com/FtlC-ian/expert-amp-server)
- Upstream tag: `v0.4.5`
- Upstream commit: `373fc5b5b9e851ae14f89c1c40c4e64816a51284`
- License: MIT; the upstream copyright and license are retained in [LICENSE](LICENSE).

The Zeus repository preserves the upstream Git history and keeps an `upstream` remote for reviewable synchronization. Official binaries expose `distribution`, `upstreamVersion`, and `upstreamCommit` through `GET /api/v1/version` so an installed appliance can be traced back to both the Zeus build and its upstream base.

## Zeus distribution layer

The Zeus SDR distribution adds:

- Zeus page styling and explicit upstream attribution;
- distribution and upstream build metadata;
- static Linux ARM64, ARMv7, and AMD64 packages;
- a hardened systemd unit and manifest-verifying operator lifecycle scripts;
- G2 installation documentation and official tag-driven release automation.

At this provenance point, amplifier protocol, serial transport, fan policy, menu navigation, control authorization, and safety behavior remain the upstream `v0.4.5` implementation. Distribution work is intentionally kept outside those paths so upstream updates can be audited clearly.

## Reproducing a release

Official release tags use the `zeus-v...` namespace. The release workflow tests the pinned source, builds all three Linux archives with `CGO_ENABLED=0`, injects the tag/commit/build date plus this upstream identity, generates SHA-256 checksums, and publishes the artifacts with GitHub CLI.

The build command is:

```bash
VERSION=zeus-vX.Y.Z CHANNEL=stable bash packaging/scripts/build-release.sh
```

Use Go 1.26.5 for the official build. The build date and archive timestamps are derived from the tagged commit time through `SOURCE_DATE_EPOCH`.

## Updating from upstream

Before changing the pinned upstream version:

1. Fetch the upstream repository and inspect the complete diff between the recorded commit and the candidate tag.
2. Keep distribution-only changes separate from amplifier/control changes.
3. Run the full Go test suite and static builds for all release architectures.
4. Update `UpstreamVersion`, `UpstreamCommit`, this document, and the release builder together.
5. Review any upstream control or safety change as functional radio software, not as packaging maintenance.
