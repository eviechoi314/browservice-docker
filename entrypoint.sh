#!/bin/sh
set -e

args="--vice-opt-http-listen-addr=${LISTEN_ADDR:-0.0.0.0:8080}"

if [ "${DISABLE_GPU:-true}" = "true" ]; then
    args="$args --chromium-args=disable-gpu"
fi

exec /opt/browservice/bin/browservice $args "$@"
