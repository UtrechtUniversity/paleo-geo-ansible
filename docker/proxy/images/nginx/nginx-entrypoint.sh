#!/bin/bash
# copyright Utrecht University
# Paleo reverse-proxy (nginx) initialization.
#
# For every site in $PALEO_SITES we:
#   1. pick its cert (own override if present, else the shared cert)
#   2. render an nginx server block (terminate TLS, proxy_pass to the backend)
#

set -uo pipefail

CERT_DIR=/etc/nginx/certs
IMPORT_DIR=/etc/import-certificates
CONF_DIR=/etc/nginx/conf.d
TPL_DIR=/etc/nginx/templates

CERT_NAME="${PALEO_CERT:-paleo}"
BACKEND_PORT="${PALEO_BACKEND_PORT:-80}"

ts()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] paleo-proxy: $*"; }

mkdir -p "$CERT_DIR" "$CONF_DIR"

# One shared HTTP->HTTPS redirects
cp "$TPL_DIR/redirect.conf" "$CONF_DIR/00-redirect.conf"

# has_import — true if an operator cert (NAME.pem + NAME.key) was found.
# In principle: import wins over reusing and self-signing certs.
has_import() {
    [ -f "$IMPORT_DIR/$1.pem" ] && [ -f "$IMPORT_DIR/$1.key" ]
}

# import_cert — copy an operator cert into the live cert dir.
import_cert() {
    say "importing operator certificate '$1'"
    cp "$IMPORT_DIR/$1.pem" "$CERT_DIR/$1.pem"
    cp "$IMPORT_DIR/$1.key" "$CERT_DIR/$1.key"
}

# self_sign cert
# The first host becomes the CN; every host is added as a SAN.
self_sign() {
    name="$1"; shift
    primary="$1"
    say "generating self-signed certificate '$name' (CN=$primary, SANs: $*)"
    cnf="/tmp/$name.cnf"
    sed "s/PALEO_CN/$primary/g" "$TPL_DIR/paleo-ssl.cnf" > "$cnf"
    {
        printf '\n[ alt_names ]\n'
        i=1
        for h in "$@"; do
            printf 'DNS.%d = %s\n' "$i" "$h"
            i=$((i + 1))
        done
    } >> "$cnf"
    if ! openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$CERT_DIR/$name.key" \
        -out    "$CERT_DIR/$name.pem" \
        -config "$cnf" \
        -extensions req_ext; then
        say "ERROR: openssl failed to generate self-signed certificate '$name'"
        say "       (kept the generated config at $cnf; check it and $TPL_DIR/paleo-ssl.cnf)"
        exit 1
    fi
    rm -f "$cnf"
}

# cert_covers NAME HOST... — true if NAME.pem is currently valid for every HOST.
cert_covers() {
    name="$1"; shift
    for h in "$@"; do
        case "$(openssl x509 -in "$CERT_DIR/$name.pem" -noout -checkhost "$h" 2>/dev/null)" in
            *"does match certificate") ;;
            *) return 1 ;;
        esac
    done
    return 0
}

ensure_cert() {
    name="$1"
    if has_import "$name"; then
        import_cert "$name"
    elif [ -f "$CERT_DIR/$name.pem" ] && [ -f "$CERT_DIR/$name.key" ] && cert_covers "$@"; then
        say "reusing existing certificate '$name'"
    else
        if [ -f "$CERT_DIR/$name.pem" ]; then
            say "certificate '$name' does not cover every requested hostname (${*:2}); regenerating"
        fi
        self_sign "$@"
    fi
    if [ ! -s "$CERT_DIR/$name.pem" ] || [ ! -s "$CERT_DIR/$name.key" ]; then
        say "ERROR: certificate bundle '$name' is missing or empty after provisioning; aborting"
        exit 1
    fi
    chmod 0600 "$CERT_DIR/$name.key"
}

# Write one TLS server block for this hostname.
render_site() {
    host="$1"; backend="$2"; cert="$3"
    say "routing https://$host -> $backend:$BACKEND_PORT (cert: $cert)"
    sed -e "s/__HOST__/$host/g" \
        -e "s/__BACKEND__/$backend/g" \
        -e "s/__PORT__/$BACKEND_PORT/g" \
        -e "s/__CERT__/$cert/g" \
        "$TPL_DIR/site.conf.template" > "$CONF_DIR/site-$host.conf"
}

if [ -z "${PALEO_SITES:-}" ]; then
    say "ERROR: PALEO_SITES is empty (expected 'host|backend host|backend')"
    exit 1
fi

# Collect the hostnames that use the SHARED cert
shared_hosts=""
for pair in $PALEO_SITES; do
    # Example of a pair: static.paleo.test|paleo-static
    case "$pair" in
        *"|"*) ;;
        *) say "ERROR: bad PALEO_SITES entry '$pair' (expected host|backend)"; exit 1 ;;
    esac
    host="${pair%%|*}"
    has_import "$host" || shared_hosts="$shared_hosts $host"
done

# Ensure the shared multi-SAN cert covering those hostnames
if [ -n "$shared_hosts" ]; then
    # shellcheck disable=SC2086
    ensure_cert "$CERT_NAME" $shared_hosts
fi

# Per-host override cert (if present) + render every server block.
for pair in $PALEO_SITES; do
    host="${pair%%|*}"
    backend="${pair##*|}"
    if has_import "$host"; then
        ensure_cert "$host" "$host"
        render_site "$host" "$backend" "$host"
    else
        render_site "$host" "$backend" "$CERT_NAME"
    fi
done

say "validating nginx configuration"
# There is no `set -e` in this script, so check explicitly. Without this the
# error below scrolls past and `exec nginx` dies with the same message anyway,
# throwing away the clear diagnostic.
if ! nginx -t; then
    say "ERROR: generated nginx configuration is invalid; aborting"
    say "       inspect $CONF_DIR/ inside the container to see what was rendered"
    exit 1
fi

say "starting nginx"
# Set nginx PID 1
exec nginx -g "daemon off;"
