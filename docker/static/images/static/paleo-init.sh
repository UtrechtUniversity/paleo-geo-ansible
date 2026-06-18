#!/bin/bash
# copyright Utrecht University
# Paleo static-site container initialization.

set -uo pipefail

CERT_DIR="/etc/apache2/certs"
CERT_IMPORTDIR="/etc/import-certificates"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }

mkdir -p "$CERT_DIR"

# static config files: replace PALEO_HOST placeholders with actual values
perl -pi -e "s/PALEO_HOST/${PALEO_HOST}/g" \
    /etc/apache2/sites-available/000-paleo-http.conf \
    /etc/apache2/sites-available/001-paleo-https.conf

# TLS certificate
# Import static certs (for production, not tested)
if [ -f "${CERT_IMPORTDIR}/paleo.pem" ] && [ -f "${CERT_IMPORTDIR}/paleo.key" ]; then
    say "Importing static TLS certificate from ${CERT_IMPORTDIR}"
    cp "${CERT_IMPORTDIR}/paleo.pem" "${CERT_DIR}/paleo.pem"
    cp "${CERT_IMPORTDIR}/paleo.key" "${CERT_DIR}/paleo.key"
    chmod 0644 "${CERT_DIR}/paleo.pem"
    chmod 0600 "${CERT_DIR}/paleo.key"
# Reuse existing certs, do nothing
elif [ -f "${CERT_DIR}/paleo.pem" ] && [ -f "${CERT_DIR}/paleo.key" ]; then
    say "Using existing self-signed certificate from previous boot"
# Generate self-signed certs
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

say "Starting Apache"
# Exec assigns PID1 to apache2, if PID1 dies, container exits
exec apache2ctl -DFOREGROUND
