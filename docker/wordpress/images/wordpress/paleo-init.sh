#!/bin/bash
# copyright Utrecht University
# Paleo WordPress container init — THIN layer on the official wordpress image.
#
# Responsibilities (Paleo-specific only):
#   1. Substitute the site hostname into our Apache vhosts.
#   2. Provide the TLS certificate Apache serves (import / reuse / self-signed).
#
# Then hand off to the official `docker-entrypoint.sh`

set -euo pipefail

CERT_DIR="/etc/apache2/certs"
CERT_IMPORTDIR="/etc/import-certificates"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }

mkdir -p "$CERT_DIR"

# Substitute PALEO_HOST into the vhost configs (idempotent: a second boot on
# the same writable layer simply finds no placeholder left to replace).
perl -pi -e "s/PALEO_HOST/${PALEO_HOST}/g" \
    /etc/apache2/sites-available/000-paleo-http.conf \
    /etc/apache2/sites-available/001-paleo-https.conf

# TLS certificate: operator-supplied import > persisted self-signed > new self-signed.
if [ -f "${CERT_IMPORTDIR}/paleo.pem" ] && [ -f "${CERT_IMPORTDIR}/paleo.key" ]; then
    say "Importing static TLS certificate from ${CERT_IMPORTDIR}"
    cp "${CERT_IMPORTDIR}/paleo.pem" "${CERT_DIR}/paleo.pem"
    cp "${CERT_IMPORTDIR}/paleo.key" "${CERT_DIR}/paleo.key"
    chmod 0644 "${CERT_DIR}/paleo.pem"
    chmod 0600 "${CERT_DIR}/paleo.key"
elif [ -f "${CERT_DIR}/paleo.pem" ] && [ -f "${CERT_DIR}/paleo.key" ]; then
    say "Using existing self-signed certificate from previous boot"
else
    say "Generating self-signed certificate for https://${PALEO_HOST}"
    perl -pi -e "s/PALEO_HOST/${PALEO_HOST}/g" /etc/ssl/paleo-ssl.cnf
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "${CERT_DIR}/paleo.key" \
        -out    "${CERT_DIR}/paleo.pem" \
        -config /etc/ssl/paleo-ssl.cnf \
        -extensions req_ext
    chmod 0600 "${CERT_DIR}/paleo.key"
fi

# Hand off to the official WordPress entrypoint.
say "Handing off to the official WordPress entrypoint"
exec docker-entrypoint.sh "$@"
