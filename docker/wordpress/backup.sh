#!/bin/bash
# copyright Utrecht University
# Paleo WordPress — on-VM backup script.
#
# Captures the *stateful* parts of a running WordPress stack into a single,
# portable backup. 
#
# What is state, and where it lives:
#   1. The database  -> MariaDB volume, captured with a logical dump (.sql).
#   2. The files      -> paleo_wp_html volume (wp-config.php, uploads, themes,
#                        plugins), captured as a tarball.
#
# Run as the `paleo` user (member of the docker group) on the VM.

set -euo pipefail

# Locate the stack
STACK_DIR="${PALEO_STACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Where finished backups land.
BACKUP_ROOT="${PALEO_BACKUP_ROOT:-${HOME}/paleo-backups/wordpress}"

# Container names
DB_CONTAINER="paleo-wp-database"
WP_CONTAINER="paleo-wp"

# Helpers
ts()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR: $*" >&2; exit 1; }

# Precheck
[ -f "${STACK_DIR}/.env" ] || die "no .env in ${STACK_DIR}; is this the stack dir?"

# Auto-export vars to env
set -a
# shellcheck disable=SC1091
source "${STACK_DIR}/.env"
# Turn off auto-export
set +a
# Exit if creds or host are missing
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD missing from .env}"
: "${PALEO_HOST:?PALEO_HOST missing from .env}"

DB_NAME="wordpress"

# Check if the containers are up
docker inspect -f '{{.State.Running}}' "${DB_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${DB_CONTAINER} is not running"
docker inspect -f '{{.State.Running}}' "${WP_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${WP_CONTAINER} is not running"

# Stage the backup
STAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_NAME="paleo-wp-${PALEO_HOST}-${STAMP}"
# Make a temp folder before the backup is sealed
WORK_DIR="$(mktemp -d)"
# Always del temp folder on exit
trap 'rm -rf "${WORK_DIR}"' EXIT
mkdir -p "${BACKUP_ROOT}"

say "Backing up WordPress site '${PALEO_HOST}' -> ${BACKUP_NAME}.tar.gz"

# 1) Database — logical dump.
say "Dumping database '${DB_NAME}'..."
docker exec -e MYSQL_PWD="${MARIADB_ROOT_PASSWORD}" "${DB_CONTAINER}" \
    mariadb-dump --single-transaction --no-tablespaces \
        -u root --databases "${DB_NAME}" \
    > "${WORK_DIR}/db.sql"

# 2) Files — tar the docroot.
say "Archiving /var/www/html..."
docker exec "${WP_CONTAINER}" tar czf - -C /var/www/html . \
    > "${WORK_DIR}/html.tar.gz"

# 3) Manifest — small metadata file for restore
WP_VERSION="$(docker exec "${WP_CONTAINER}" \
    sh -c 'grep -m1 "\$wp_version =" /var/www/html/wp-includes/version.php | cut -d"'"'"'" -f2' \
    2>/dev/null || echo unknown)"
cat > "${WORK_DIR}/manifest.env" <<EOF
# Paleo WordPress backup manifest
PALEO_BACKUP_KIND=wordpress
PALEO_BACKUP_CREATED=$(ts)
PALEO_HOST=${PALEO_HOST}
PALEO_SITE_URL=https://${PALEO_HOST}
WORDPRESS_VERSION=${WP_VERSION}
DB_NAME=${DB_NAME}
EOF

# Seal the backup
tar czf "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" -C "${WORK_DIR}" \
    db.sql html.tar.gz manifest.env

say "Done: ${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"
say "Size: $(du -h "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" | cut -f1)"
