#!/bin/bash
# copyright Utrecht University
# Paleo WordPress container bootstrap.
#
# Pattern borrowed from matomo-ansible/docker/images/matomo/matomo-init.sh:

set -uo pipefail

INIT_FLAG="/var/www/html/.paleo-initialized"
CERT_DIR="/etc/apache2/certs"
CERT_IMPORTDIR="/etc/import-certificates"
WP_PATH="/var/www/html"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }

mkdir -p "$CERT_DIR"

# Substitute PALEO_HOST into static config files
perl -pi -e "s/PALEO_HOST/${PALEO_HOST}/g" \
    /etc/apache2/sites-available/000-paleo-http.conf \
    /etc/apache2/sites-available/001-paleo-https.conf

# TLS certificate
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

# Wait for the database
say "Waiting for database at ${WORDPRESS_DB_HOST}:3306"
until mysql \
        -h"${WORDPRESS_DB_HOST}" \
        -u"${WORDPRESS_DB_USER}" \
        -p"${WORDPRESS_DB_PASSWORD}" \
        -e "SELECT 1" >/dev/null 2>&1; do
    sleep 1
done
say "Database is up"

# First-run WordPress install
if [ ! -f "$INIT_FLAG" ]; then
    set -e
    say "First run — installing WordPress"

    # Generate wp-config.php (fresh salts come from the WordPress.org API,
    sudo -u www-data wp config create \
        --dbname="${WORDPRESS_DB_NAME}" \
        --dbuser="${WORDPRESS_DB_USER}" \
        --dbpass="${WORDPRESS_DB_PASSWORD}" \
        --dbhost="${WORDPRESS_DB_HOST}" \
        --path="${WP_PATH}" \
        --force \
        --extra-php <<'PHP'
// Run WordPress behind Apache that terminates TLS — trust the server vars.
if (isset($_SERVER['HTTPS']) === false && (
        (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ||
        (isset($_SERVER['HTTP_X_FORWARDED_SSL'])   && $_SERVER['HTTP_X_FORWARDED_SSL']   === 'on'))) {
    $_SERVER['HTTPS'] = 'on';
}
PHP

    sudo -u www-data wp core install \
        --url="https://${PALEO_HOST}" \
        --title="${PALEO_FIRST_SITE_TITLE}" \
        --admin_user="${PALEO_FIRST_USER_NAME}" \
        --admin_email="${PALEO_FIRST_USER_EMAIL}" \
        --admin_password="${PALEO_FIRST_USER_PASSWORD}" \
        --skip-email \
        --path="${WP_PATH}"

    # Visible demo content for browsering url
    sudo -u www-data wp post create \
        --post_type=page \
        --post_status=publish \
        --post_title="About Paleo Earth" \
        --post_content="<p>This is a demonstration site for the Paleo Earth research group at Utrecht University. Deployed via the paleo-ansible Docker LAMP base.</p>" \
        --path="${WP_PATH}"

    touch "$INIT_FLAG"
    chown www-data:www-data "$INIT_FLAG"
    say "WordPress initialized"
    set +e
fi

say "Starting Apache"
exec apache2-foreground
