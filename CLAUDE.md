# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Provide a fully Dockerized build of [browservice](https://github.com/ttalvitie/browservice) — a web proxy server that renders a modern browser server-side and streams it to lightweight/retro clients. Key requirements:

- Dockerfile(s) must build cleanly on both Docker and Podman
- Pre-built images published to GHCR (`ghcr.io/...`)
- Automated builds via GitHub Actions

## Architecture Intent

This is an infrastructure/packaging project, not an application. The expected structure when built out:

- `Dockerfile` — multi-stage build: compile browservice from source, then produce a minimal runtime image
- `.github/workflows/` — CI/CD: build and push to GHCR on push/release
- No application code lives here; browservice source is pulled at build time (upstream repo or pinned release tarball)

## Key Constraints

- browservice has heavy dependencies (Chromium, CEF, or similar); the Docker build will be large and slow — use multi-stage builds and layer caching carefully
- Must target amd64 at minimum; arm64 support is desirable if upstream supports it
- Podman compatibility means avoiding Docker-specific syntax (`--mount=type=secret`, etc.) unless there's a fallback
