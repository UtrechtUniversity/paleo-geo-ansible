#!/bin/bash
# copyright Utrecht University
# Paleo WordPress — on-VM restore script (disaster recovery, same host).
#
# Consumes ONE backup produced by backup.sh:
#     paleo-wp-<host>-<stamp>.tar.gz
#       ├── db.sql          logical DB dump
#       ├── html.tar.gz     /var/www/html (wp-config.php, uploads, themes…)
#       └── manifest.env    host, site URL, WP version, created-at
#
# Run as the `paleo` user.

set -euo pipefail

# Args
BACKUP=""
FORCE=0

usage() {
    cat >&2 <<EOF
Usage: restore.sh --backup <file.tar.gz> [--force]

  --backup   Backup tarball produced by backup.sh (required).
  --force    Skip the interactive "this overwrites the live site" prompt.
EOF
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --backup)   BACKUP="$2"; shift 2 ;;
        --force)    FORCE=1; shift ;;
        -h|--help)  usage ;;
        *)          echo "Unknown argument: $1" >&2; usage ;;
    esac
done

[ -n "${BACKUP}" ] || usage
[ -f "${BACKUP}" ] || { echo "Backup not found: ${BACKUP}" >&2; exit 2; }

# Locate the stack
STACK_DIR="${PALEO_STACK_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DB_CONTAINER="paleo-wp-database"
WP_CONTAINER="paleo-wp"
DB_NAME="wordpress"

ts()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR: $*" >&2; exit 1; }

[ -f "${STACK_DIR}/.env" ] || die "no .env in ${STACK_DIR}; is this the stack dir?"
set -a; # shellcheck disable=SC1091
source "${STACK_DIR}/.env"; set +a
: "${MARIADB_ROOT_PASSWORD:?MARIADB_ROOT_PASSWORD missing from .env}"

docker inspect -f '{{.State.Running}}' "${DB_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${DB_CONTAINER} is not running (start the stack first)"
docker inspect -f '{{.State.Running}}' "${WP_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${WP_CONTAINER} is not running (start the stack first)"

# Unpack and validate the backup
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
say "Unpacking backup..."
tar xzf "${BACKUP}" -C "${WORK_DIR}"
for f in db.sql html.tar.gz manifest.env; do
    [ -f "${WORK_DIR}/${f}" ] || die "backup missing ${f}; not a valid backup file?"
done
source "${WORK_DIR}/manifest.env"
say "Backup: host=${PALEO_HOST:-?} wp=${WORDPRESS_VERSION:-?} created=${PALEO_BACKUP_CREATED:-?}"

# Confirm
if [ "${FORCE}" -ne 1 ]; then
    echo "This will OVERWRITE the live WordPress database and files on this host." >&2
    read -r -p "Type 'yes' to proceed: " reply
    [ "${reply}" = "yes" ] || die "aborted by operator"
fi

# 1) Restore the database
say "Restoring database '${DB_NAME}'..."
docker exec -i -e MYSQL_PWD="${MARIADB_ROOT_PASSWORD}" "${DB_CONTAINER}" \
    mariadb -u root < "${WORK_DIR}/db.sql"

# 2) Restore the files
say "Wiping and repopulating /var/www/html..."
# * does not remove dotfiles e.g. .env. Hence ugly pattern added
docker exec "${WP_CONTAINER}" sh -c 'rm -rf /var/www/html/* /var/www/html/.[!.]* /var/www/html/..?* 2>/dev/null || true'
docker exec -i "${WP_CONTAINER}" tar xzf - -C /var/www/html < "${WORK_DIR}/html.tar.gz"
docker exec "${WP_CONTAINER}" chown -R www-data:www-data /var/www/html

# Restart container
say "Restarting ${WP_CONTAINER}..."
docker restart "${WP_CONTAINER}" >/dev/null

say "Restore complete."
