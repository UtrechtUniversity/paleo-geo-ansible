#!/bin/bash
# copyright Utrecht University
# Smoke test for the Paleo reverse-proxy image.
#
# WHY THIS
# The proxy's nginx configuration and its TLS certificate do not exist in this
# repository. This test asserts on outcomes such as SAN lists, generated filenames.
#
# Usage:
#   docker build -t paleo-nginx:smoke docker/proxy/images/nginx
#   ./docker/proxy/images/nginx/smoke-test.sh paleo-nginx:smoke

set -uo pipefail

IMAGE="${1:-paleo-nginx:smoke}"
VOL="paleo-smoke-certs-$$"
CTR="paleo-smoke-$$"
IMPORTDIR="$(mktemp -d)"

fails=0
info()   { printf '\n== %s\n' "$*"; }
pass()   { printf '  PASS  %s\n' "$*"; }
fail()   { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
assert() {
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1"
        printf '          expected: %s\n' "$2"
        printf '          actual:   %s\n' "$3"
    fi
}

# shellcheck disable=SC2329
cleanup() {
    docker rm -f "$CTR" >/dev/null 2>&1
    docker volume rm -f "$VOL" >/dev/null 2>&1
    rm -rf "$IMPORTDIR"
}
trap cleanup EXIT

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "ERROR: image '$IMAGE' not found. Build it first:"
    echo "  docker build -t $IMAGE $(dirname "$0")"
    exit 2
fi

# boot sites, start the proxy with the given PALEO_SITES, on the SHARED cert
boot() {
    docker rm -f "$CTR" >/dev/null 2>&1
    docker run -d --name "$CTR" \
        -v "$VOL:/etc/nginx/certs" \
        -v "$IMPORTDIR:/etc/import-certificates:ro" \
        -e PALEO_SITES="$1" \
        "$IMAGE" >/dev/null || return 1
    for _ in $(seq 40); do
        if [ "$(docker inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null)" != "true" ]; then
            return 1
        fi
        if docker exec "$CTR" bash -c 'exec 3<>/dev/tcp/127.0.0.1/443' >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

# Check the shared certificate content.
sans() {
    docker run --rm -v "$VOL:/etc/nginx/certs" --entrypoint openssl "$IMAGE" \
        x509 -in /etc/nginx/certs/paleo.pem -noout -ext subjectAltName 2>/dev/null \
        | tr ',' '\n' | sed -n 's/.*DNS:\([^ ]*\).*/\1/p' | sort | tr '\n' ' ' | sed 's/ *$//'
}

# Identifies the certificate
fingerprint() {
    docker run --rm -v "$VOL:/etc/nginx/certs" --entrypoint openssl "$IMAGE" \
        x509 -in /etc/nginx/certs/paleo.pem -noout -fingerprint -sha256 2>/dev/null
}

confd() {
    docker exec "$CTR" ls /etc/nginx/conf.d/ 2>/dev/null | sort | tr '\n' ' ' | sed 's/ *$//'
}

sni_accepted() {
    docker exec "$CTR" sh -c \
        "echo | openssl s_client -connect 127.0.0.1:443 -servername $1 2>&1" \
        | grep -q '^subject='
}

echo "Smoke-testing $IMAGE"

################################################################################
info "TEST 1 — first boot generates config and a covering certificate"

if boot "a.test|backend-a b.test|backend-b"; then
    pass "container boots and serves TLS"
    assert "one server block per site, plus the catch-all" \
        "00-redirect.conf site-a.test.conf site-b.test.conf" "$(confd)"
    assert "certificate covers both hostnames" "a.test b.test" "$(sans)"
else
    fail "container boots and serves TLS"
    docker logs "$CTR" 2>&1 | tail -20
fi

################################################################################
info "TEST 2 — adding a site regenerates the certificate to cover it"

before="$(fingerprint)"
if boot "a.test|backend-a b.test|backend-b c.test|backend-c"; then
    assert "certificate now covers the added hostname" "a.test b.test c.test" "$(sans)"
    assert "config generated for the added site" \
        "00-redirect.conf site-a.test.conf site-b.test.conf site-c.test.conf" "$(confd)"
    if [ "$(fingerprint)" != "$before" ]; then
        pass "certificate was actually replaced, not reused"
    else
        fail "certificate was actually replaced, not reused"
    fi
else
    fail "container boots with the added site"
    docker logs "$CTR" 2>&1 | tail -20
fi

################################################################################
info "TEST 3 — an unchanged site list reuses the certificate"

before="$(fingerprint)"
if boot "a.test|backend-a b.test|backend-b c.test|backend-c"; then
    assert "certificate is byte-identical across a plain restart" "$before" "$(fingerprint)"
else
    fail "container boots on restart"
fi

################################################################################
info "TEST 4 — only configured hostnames are served"

if sni_accepted a.test; then pass "configured hostname completes a handshake"
else fail "configured hostname completes a handshake"; fi

if sni_accepted unknown.test; then
    fail "unconfigured hostname is rejected (it was served instead)"
else
    pass "unconfigured hostname is rejected"
fi

################################################################################
info "TEST 5 — an empty site list is a hard error"

docker rm -f "$CTR" >/dev/null 2>&1
docker run --name "$CTR" -v "$VOL:/etc/nginx/certs" -e PALEO_SITES="" "$IMAGE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    pass "empty PALEO_SITES exits non-zero (got $rc)"
else
    fail "empty PALEO_SITES exits non-zero (got 0)"
fi

################################################################################
info "TEST 6 — an operator certificate that misses a hostname is used, but warned about"

openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
    -keyout "$IMPORTDIR/paleo.key" -out "$IMPORTDIR/paleo.pem" \
    -subj "/CN=operator-supplied" -addext "subjectAltName=DNS:a.test" >/dev/null 2>&1
imported_fp="$(openssl x509 -in "$IMPORTDIR/paleo.pem" -noout -fingerprint -sha256)"

if boot "a.test|backend-a b.test|backend-b"; then
    assert "operator certificate is used as-is, not regenerated" \
        "$imported_fp" "$(fingerprint)"
    # For a warning the log is the observable.
    if docker logs "$CTR" 2>&1 | grep -q "does not cover"; then
        pass "the uncovered hostname is reported"
    else
        fail "the uncovered hostname is reported"
    fi
else
    fail "container boots with an operator certificate"
    docker logs "$CTR" 2>&1 | tail -20
fi

################################################################################
echo
if [ "$fails" -eq 0 ]; then
    echo "All smoke tests passed."
    exit 0
fi
echo "$fails smoke test(s) FAILED."
exit 1
