#!/bin/bash
# Smoke test for the RT container image.
set -euo pipefail

IMAGE="${1:-docker.io/colonwq/rt5:510-5}"
NETWORK="${RT_TEST_NETWORK:-rt5-test}"
MARIADB_IMAGE="${RT_TEST_MARIADB_IMAGE:-docker.io/mariadb:lts-ubi}"
HOST_PORT="${RT_TEST_PORT:-18080}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="${ROOT}/config"

cleanup() {
    podman rm -f rt5-test mariadb-test 2>/dev/null || true
}
trap cleanup EXIT

podman network exists "$NETWORK" || podman network create "$NETWORK"
cleanup

podman run -d --name mariadb-test --network "$NETWORK" --network-alias mariadb \
    -e MARIADB_ROOT_PASSWORD=rootpass \
    -e MARIADB_DATABASE=rt5 \
    -e MARIADB_USER=rt_user \
    -e MARIADB_PASSWORD=rt_pass \
    "$MARIADB_IMAGE"

echo "Waiting for mariadb..."
for i in $(seq 1 60); do
    if podman exec mariadb-test mariadb-admin ping -urt_user -prt_pass --silent 2>/dev/null; then
        break
    fi
    sleep 2
done

podman run -d --name rt5-test --network "$NETWORK" \
    -p "${HOST_PORT}:8080" \
    -v "${CONFIG_DIR}/rt5.conf:/etc/httpd/conf.d/rt5.conf:Z" \
    -v "${CONFIG_DIR}/msmtprc:/etc/msmtprc:Z" \
    -v rt5-test-attachments:/attachments:Z \
    "$IMAGE"

podman cp "${CONFIG_DIR}/RT_SiteConfig.pm.test" rt5-test:/opt/rt5/etc/RT_SiteConfig.pm
podman exec rt5-test chmod 664 /opt/rt5/etc/RT_SiteConfig.pm

echo "Initializing RT database..."
podman exec -u default rt5-test /opt/rt5/sbin/rt-setup-database \
    --action init --skip-create --dba-password rootpass

echo "Waiting for httpd..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:${HOST_PORT}/" >/tmp/rt5-test.html 2>/dev/null; then
        break
    fi
    sleep 2
done

if grep -qi 'internal server error' /tmp/rt5-test.html; then
    echo "FAIL: HTTP 500 response"
    podman logs rt5-test 2>&1 | tail -30
    exit 1
fi

if ! grep -qiE 'login|request tracker|rt' /tmp/rt5-test.html; then
    echo "FAIL: unexpected response body"
    head -20 /tmp/rt5-test.html
    podman logs rt5-test 2>&1 | tail -30
    exit 1
fi

echo "PASS: RT responded on http://localhost:${HOST_PORT}/"
head -5 /tmp/rt5-test.html
