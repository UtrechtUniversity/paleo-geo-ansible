#!/bin/bash
# copyright Utrecht University
# Paleo static site — on-VM restore script.
#
# Consumes ONE backup produced by backup.sh:
#     paleo-static-<host>-<stamp>.tar.gz
#       ├── html.tar.gz     /var/www/html
#       └── manifest.env    host, site URL, created-at
#
# Run as the `paleo` user.

set -euo pipefail

# Args
BACKUP=""
FORCE=0

usage() {
    cat >&2 <<EOF
Usage: restore.sh --backup <file.tar.gz> [--force]

  --backup   Backup tar produced by backup.sh (required).
  --force    Skip the interactive "this overwrites the existing docroot" prompt.
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
STATIC_CONTAINER="paleo-static"

ts()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }
die() { echo "[$(ts)] ERROR: $*" >&2; exit 1; }

[ -f "${STACK_DIR}/.env" ] || die "no .env in ${STACK_DIR}; is this the stack dir?"

docker inspect -f '{{.State.Running}}' "${STATIC_CONTAINER}" 2>/dev/null | grep -q true \
    || die "${STATIC_CONTAINER} is not running (start the stack first)"

# Unpack and validate the backup
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
say "Unpacking backup..."
tar xzf "${BACKUP}" -C "${WORK_DIR}"
for f in html.tar.gz manifest.env; do
    [ -f "${WORK_DIR}/${f}" ] || die "backup missing ${f}; not a valid backup file?"
done
# shellcheck source=/dev/null
source "${WORK_DIR}/manifest.env"
say "Backup: host=${PALEO_HOST:-?} created=${PALEO_BACKUP_CREATED:-?}"

# Confirm
if [ "${FORCE}" -ne 1 ]; then
    echo "This will OVERWRITE the existing docroot on this host." >&2
    read -r -p "Type 'yes' to proceed: " reply
    [ "${reply}" = "yes" ] || die "aborted by operator"
fi

# Restore the files
say "Wiping and populating /var/www/html..."
# * does not remove dotfiles e.g. .env. Hence ugly pattern added
docker exec "${STATIC_CONTAINER}" sh -c 'rm -rf /var/www/html/* /var/www/html/.[!.]* /var/www/html/..?* 2>/dev/null || true'
docker exec -i "${STATIC_CONTAINER}" tar xzf - -C /var/www/html < "${WORK_DIR}/html.tar.gz"
docker exec "${STATIC_CONTAINER}" chown -R www-data:www-data /var/www/html

# Restart container
say "Restarting ${STATIC_CONTAINER}..."
docker restart "${STATIC_CONTAINER}" >/dev/null

say "Restore complete."
