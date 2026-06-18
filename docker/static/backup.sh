#!/bin/bash
# copyright Utrecht University
# Paleo static site — on-VM backup script.
#
# In short:
#   The docroot -> paleo_static_html volume (/var/www/html), captured as a tar.
#
# Produces ONE timestamped backup:
#     paleo-static-<host>-<stamp>.tar.gz
#       ├── html.tar.gz     /var/www/html
#       └── manifest.env    host, site URL, created-at

set -euo pipefail

# Locate the stack
STACK_DIR="${PALEO_STACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Where finished backups land.
BACKUP_ROOT="${PALEO_BACKUP_ROOT:-${HOME}/paleo-backups/static}"

# Container name
STATIC_CONTAINER="paleo-static"

# Helpers
ts()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR: $*" >&2; exit 1; }

# Precheck
[ -f "${STACK_DIR}/.env" ] || die "no .env in ${STACK_DIR}; is this the stack dir?"

# Auto-export vars to env
set -a
source "${STACK_DIR}/.env"
# Turn off auto-export
set +a
# Exit if PALEO_HOST is empty
: "${PALEO_HOST:?PALEO_HOST missing from .env}"

# Check if the container is up
docker inspect -f '{{.State.Running}}' "${STATIC_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${STATIC_CONTAINER} is not running"

# Stage the backup
STAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_NAME="paleo-static-${PALEO_HOST}-${STAMP}"
# Make a temp folder before the backup is sealed
WORK_DIR="$(mktemp -d)"
# Always del temp folder on exit
trap 'rm -rf "${WORK_DIR}"' EXIT
mkdir -p "${BACKUP_ROOT}"

say "Backing up static site '${PALEO_HOST}' -> ${BACKUP_NAME}.tar.gz"

# 1) Files — tar the docroot.
say "Archiving /var/www/html..."
docker exec "${STATIC_CONTAINER}" tar czf - -C /var/www/html . \
    > "${WORK_DIR}/html.tar.gz"

# 2) Manifest — small metadata file for restore
cat > "${WORK_DIR}/manifest.env" <<EOF
# Paleo static backup manifest
PALEO_BACKUP_KIND=static
PALEO_BACKUP_CREATED=$(ts)
PALEO_HOST=${PALEO_HOST}
PALEO_SITE_URL=https://${PALEO_HOST}
EOF

# Seal the backup
tar czf "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" -C "${WORK_DIR}" \
    html.tar.gz manifest.env

say "Done: ${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"
say "Size: $(du -h "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" | cut -f1)"
