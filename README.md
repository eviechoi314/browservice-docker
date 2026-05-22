# browservice-docker

A fully Dockerized build of [browservice](https://github.com/ttalvitie/browservice) — a proxy server that renders a modern Chromium browser server-side and streams it to lightweight or retro clients over HTTP. Run a real browser on old hardware, thin clients, or anywhere you'd rather not install a full browser stack.

Pre-built images are published to GHCR and updated automatically via GitHub Actions.

## Quick start

```bash
docker run -d \
  --cap-add=SYS_ADMIN \
  -p 8080:8080 \
  ghcr.io/eviechoi314/browservice-docker:latest
```

Then open `http://<your-host>:8080` in any browser — even a very old one.

> **`--cap-add=SYS_ADMIN` is required.** Chromium's process sandbox needs this capability to isolate renderer processes. Without it, the browser won't start. For Docker Compose, use `cap_add: [SYS_ADMIN]`.

### Docker Compose

```yaml
services:
  browservice:
    image: ghcr.io/eviechoi314/browservice-docker:latest
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    ports:
      - "8080:8080"
```

With GPU passthrough:

```yaml
services:
  browservice:
    image: ghcr.io/eviechoi314/browservice-docker:feature-vaapi-noble
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    devices:
      - /dev/dri/renderD128
    environment:
      DISABLE_GPU: "false"
    ports:
      - "8080:8080"
```

## Available tags

| Tag | Description |
|---|---|
| `latest` | Latest build from `main` (Ubuntu 22.04 runtime) |
| `main` | Same as `latest` |
| `feature-vaapi-noble` | Ubuntu 24.04 runtime — full VA-API hardware video decode support |

Pinned version tags (e.g. `v0.9.12.2`) will be added once a tagging workflow is in place.

## Configuration

Two environment variables control the main options:

| Variable | Default | Description |
|---|---|---|
| `LISTEN_ADDR` | `0.0.0.0:8080` | Bind address for the HTTP server |
| `DISABLE_GPU` | `true` | Pass `--chromium-args=disable-gpu` to Chromium. Set to `false` with a DRI device mounted for GPU/VA-API |
| `CHROMIUM_EXTRA_ARGS` | _(unset)_ | Additional comma-separated args forwarded to Chromium (e.g. `use-angle=default,enable-features=VaapiVideoDecoder`) |

Any additional browservice flags can be appended as command arguments and will be passed through directly.

```bash
# Custom port
docker run -d --cap-add=SYS_ADMIN -e LISTEN_ADDR=0.0.0.0:9090 -p 9090:9090 \
  ghcr.io/eviechoi314/browservice-docker:latest

# GPU passthrough with ANGLE (Intel/AMD open-source drivers)
# Find your render node with: ls /dev/dri/  — typically renderD128, or renderD129 if you have multiple GPUs
docker run -d --cap-add=SYS_ADMIN --device=/dev/dri/renderD128 \
  -e DISABLE_GPU=false \
  -e CHROMIUM_EXTRA_ARGS="use-angle=default,enable-features=VaapiVideoDecoder" \
  -p 8080:8080 \
  ghcr.io/eviechoi314/browservice-docker:latest
```

> **VA-API note:** The `latest`/`main` image (Ubuntu 22.04 runtime) includes `mesa-va-drivers` and `intel-media-va-driver-non-free`, but VA-API video decode requires libva ≥ 1.17 and Ubuntu 22.04 ships 1.14 — so hardware video decode won't activate. GPU rasterization via ANGLE still works fine.
>
> Use the `feature-vaapi-noble` tag (Ubuntu 24.04 runtime, libva 2.20) for full VA-API hardware video decode support.

For the full list of browservice options:

```bash
docker run --rm ghcr.io/eviechoi314/browservice-docker:latest --help
```

## Building locally

```bash
git clone https://github.com/eviechoi314/browservice-docker.git
cd browservice-docker
docker build -t browservice-docker .
```

The build pulls the browservice source and a pre-built patched CEF tarball from the upstream GitHub release, compiles everything, and produces a ~555 MB runtime image. It will take a few minutes — get a coffee.

To target a specific browservice release:

```bash
docker build --build-arg BROWSERVICE_VERSION=v0.9.12.2 -t browservice-docker .
```

## How it works

The Dockerfile is a two-stage build:

1. **Builder** — Ubuntu 22.04 with full build toolchain. Clones browservice at the pinned version, downloads the matching patched CEF tarball, compiles the CEF DLL wrapper, then builds browservice itself with `make release`.
2. **Runtime** — Ubuntu 24.04 (Noble) with only the runtime libraries needed by browservice and CEF. The compiled `release/bin/` directory is copied over. A non-root `browservice` user runs the process; `chrome-sandbox` retains its root:root setuid bit so Chromium's sandbox still works.

The builder stays on Ubuntu 22.04 to match upstream's build environment; the resulting binaries run fine on 24.04 thanks to glibc forward-compatibility.

browservice manages its own Xvfb virtual display internally — no display server needs to be provided externally.

## Platform support

- `linux/amd64` — built and tested
- `linux/arm64` — built and pushed by CI; tested on Raspberry Pi CM5

## Upstream

This project packages [browservice by Toni Talvitie](https://github.com/ttalvitie/browservice). All credit for the actual software goes there.
