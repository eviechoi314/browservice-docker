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

Two-stage build, both on `ubuntu:22.04` (matches upstream AppImage builds):

**Builder stage**
- Installs build toolchain + `lbzip2` (required by `setup_cef.sh` to extract the CEF tarball)
- Installs all CEF link-time `-dev` packages — `libcef.so` has NEEDED entries for nss, dbus, alsa, cups, atk, atspi, xdamage, xfixes that the linker must resolve at build time even though they're runtime libs
- Clones browservice at `BROWSERVICE_VERSION`, downloads matching `patched_cef_<arch>.tar.bz2` from the upstream GitHub release
- Runs `./setup_cef.sh` (compiles the CEF DLL wrapper via CMake), then `make -j$(nproc) release`
- Sets `chrome-sandbox` to root:root 4755 (setuid) — must be done in the build layer while running as root

**Runtime stage**
- Only runtime libraries: `libpocofoundation80 libpoconet80` (not `libpoco-dev`; the ABI suffix on Ubuntu 22.04 is `80`)
- Pre-creates `/tmp/.X11-unix` with sticky bit (1777) so Xvfb can bind its socket as a non-root user
- Creates a `browservice` system user with a home directory (`--create-home`) — browservice writes its data to `~/.browservice` on startup
- Runs as `USER browservice` — Chromium refuses to start as root without `--no-sandbox`
- browservice manages its own Xvfb internally; no `xvfb-run` wrapper in the entrypoint
- Default entrypoint binds to `0.0.0.0:8080` via `--vice-opt-http-listen-addr`

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
- amd64 is the primary target; arm64 and armhf CEF tarballs exist upstream if multi-platform builds are added later
