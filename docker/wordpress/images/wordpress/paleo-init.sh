#!/bin/bash
# copyright Utrecht University
#
# What it does: substitute the site hostname into our
# Apache vhost.

set -euo pipefail

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
say() { echo "[$(ts)] $*"; }

perl -pi -e "s/PALEO_HOST/${PALEO_HOST}/g" \
    /etc/apache2/sites-available/000-paleo-http.conf

say "Handing off to the official WordPress entrypoint"
exec docker-entrypoint.sh "$@"
