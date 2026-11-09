#!/usr/bin/env bash
# Sandboxed AI Observer: app on an --internal network (no route out), only a
# dumb TCP forwarder is published, and only on host loopback.
set -euo pipefail
cd "$(dirname "$0")"
APP=ai-observer-sandbox:local; FWD=ai-observer-fwd:local
NET_IN=aiobs-internal; NET_OUT=aiobs-edge; VOL=aiobs-data
TOKEN_FILE=.token

build() {
  case "$(uname -m)" in arm64|aarch64) A=arm64;; *) A=amd64;; esac
  docker build --build-arg TARGETARCH=$A --build-arg VERSION=sandbox -t $APP ..
  docker build -t $FWD forwarder
}

case "${1:-up}" in
build) build ;;
up)
  docker image inspect $APP >/dev/null 2>&1 && docker image inspect $FWD >/dev/null 2>&1 || build
  [ -f $TOKEN_FILE ] || { umask 077; openssl rand -hex 24 > $TOKEN_FILE; }
  TOKEN=$(cat $TOKEN_FILE)
  docker network inspect $NET_IN >/dev/null 2>&1 || docker network create --internal $NET_IN >/dev/null
  docker network inspect $NET_OUT >/dev/null 2>&1 || docker network create $NET_OUT >/dev/null
  docker volume inspect $VOL >/dev/null 2>&1 || docker volume create $VOL >/dev/null
  docker rm -f aiobs aiobs-fwd >/dev/null 2>&1 || true
  docker run -d --name aiobs --hostname aiobs \
    --network $NET_IN --network-alias aiobs \
    --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
    --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit 256 --memory 1g --cpus 2 \
    --user 65532:65532 --restart unless-stopped \
    -v $VOL:/app/data \
    -e AI_OBSERVER_AUTH_TOKEN="$TOKEN" \
    -e AI_OBSERVER_REDACT=all \
    -e AI_OBSERVER_RETENTION_DAYS=30 \
    -e AI_OBSERVER_ALLOWED_HOSTS=localhost \
    $APP serve >/dev/null
  # forwarder: created on the edge net (needed to publish ports), then also joined to the internal net
  docker create --name aiobs-fwd --network $NET_OUT \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit 64 --memory 64m --restart unless-stopped \
    -p 127.0.0.1:${UI_PORT:-8080}:8080 -p 127.0.0.1:${OTLP_PORT:-4319}:4318 \
    $FWD 8080=aiobs:8080 4318=aiobs:4318 >/dev/null
  docker network connect $NET_IN aiobs-fwd
  docker start aiobs-fwd >/dev/null
  echo "UI:   http://localhost:8080/?token=$TOKEN"
  echo "OTLP: http://localhost:${OTLP_PORT:-4319}  (header: Authorization=Bearer $TOKEN)"
  ;;
down) docker rm -f aiobs aiobs-fwd ;;
nuke) docker rm -f aiobs aiobs-fwd 2>/dev/null; docker network rm $NET_IN $NET_OUT; docker volume rm $VOL ;;
logs) docker logs --tail 100 "${2:-aiobs}" ;;
*) echo "usage: $0 build|up|down|nuke|logs [aiobs|aiobs-fwd]"; exit 1 ;;
esac
