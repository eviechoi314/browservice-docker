# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Packaging-only repo — no application code. It Dockerizes [browservice](https://github.com/ttalvitie/browservice), a server-side Chromium proxy. The browservice source and patched CEF tarball are pulled from upstream at build time.

## Build commands

```bash
# Standard build
docker build -t browservice-docker .

# Pin a specific upstream version
docker build --build-arg BROWSERVICE_VERSION=v0.9.12.2 -t browservice-docker .

# Run locally (--cap-add=SYS_ADMIN is mandatory — see Runtime section)
docker run -d --cap-add=SYS_ADMIN -p 8080:8080 browservice-docker
```

## Dockerfile structure

Two-stage build. Builder on `ubuntu:22.04` (matches upstream AppImage builds); runtime on `ubuntu:24.04` (Noble) for libva ≥ 1.17 VA-API support. Binaries built on 22.04 run fine on 24.04 — glibc is forward-compatible.

**Builder stage**
- Installs build toolchain + `lbzip2` (required by `setup_cef.sh` to extract the CEF tarball)
- Installs all CEF link-time `-dev` packages — `libcef.so` has NEEDED entries for nss, dbus, alsa, cups, atk, atspi, xdamage, xfixes that the linker must resolve at build time even though they're runtime libs
- Clones browservice at `BROWSERVICE_VERSION`, downloads matching `patched_cef_<arch>.tar.bz2` from the upstream GitHub release
- Runs `./setup_cef.sh` (compiles the CEF DLL wrapper via CMake), then `make -j$(nproc) release`
- Sets `chrome-sandbox` to root:root 4755 (setuid) — must be done in the build layer while running as root

**Runtime stage**
- Only runtime libraries. Ubuntu 24.04 t64 ABI transition renames several packages:
  - `libpocofoundation80t64 libpoconet80t64` (was `libpocofoundation80 libpoconet80`)
  - `libasound2t64` (was `libasound2`)
  - `libcups2t64` (was `libcups2`)
- `intel-media-va-driver-non-free` is x86-only — installed conditionally via `dpkg --print-architecture` check so arm64 builds succeed
- Pre-creates `/tmp/.X11-unix` with sticky bit (1777) so Xvfb can bind its socket as a non-root user
- Creates a `browservice` system user with a home directory (`--create-home`) — browservice writes its data to `~/.browservice` on startup
- Runs as `USER browservice` — Chromium refuses to start as root without `--no-sandbox`
- browservice manages its own Xvfb internally; no `xvfb-run` wrapper in the entrypoint
- Default entrypoint binds to `0.0.0.0:8080` via `--vice-opt-http-listen-addr`

## VA-API / GPU support

- `DISABLE_GPU=true` (default): passes `--chromium-args=disable-gpu`. Safe for headless/CPU-only use.
- `DISABLE_GPU=false` + a DRI device mounted: enables GPU rasterization. Use `use-angle=default` via `CHROMIUM_EXTRA_ARGS` for ANGLE/open-source drivers (Intel/AMD).
- Full VA-API hardware video decode requires libva ≥ 1.17. Ubuntu 22.04 ships 1.14 (insufficient); Ubuntu 24.04 ships 2.20 (works). The `feature-vaapi-noble` / runtime-24.04 image is needed for hardware video decode.
- `intel-media-va-driver-non-free` covers Intel Gen8+ iGPUs on amd64. `mesa-va-drivers` covers AMD (radeonsi) and open-source Intel on both arches.
- ANGLE flag is `use-angle=default`, not `use-gl=egl` — the latter is rejected by this CEF version.

## Runtime requirements

The Chromium sandbox requires `SYS_ADMIN`. Containers must be started with:
```bash
--cap-add=SYS_ADMIN
```
Without it, Chromium's zygote process fails to initialize and the browser doesn't start.

## GitHub Actions

`.github/workflows/build.yml` builds and pushes to `ghcr.io/eviechoi314/browservice-docker` on every push to `main` and on version tags. Uses GHA layer cache (`type=gha`) for faster incremental builds. PRs build but do not push.

`FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true` is set in the workflow env — GitHub is forcing Node.js 24 as the Actions runtime default from June 2026.

## Git / SSH

Use `GIT_SSH_COMMAND="ssh -i ~/.ssh/id_rsa -o IdentitiesOnly=yes"` for all git push/pull. The `id_ed25519` key is for a different account.

## Key constraints

- The Docker build is slow (~7 min on GitHub-hosted runners, faster locally with cache) — always use `--build-arg` caching where possible
- Podman compatibility: avoid Docker-specific syntax (`--mount=type=secret`, etc.)
- amd64 and arm64 are built and pushed by CI; armhf CEF tarballs exist upstream but are not yet wired up
- arm64 tested on Raspberry Pi CM5
