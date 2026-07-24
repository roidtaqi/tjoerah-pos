#!/usr/bin/env sh

set -eu

php artisan migrate --force

case "${SEED_DEMO_DATA:-false}" in
    1|true|TRUE|yes|YES)
        php artisan db:seed --force
        ;;
esac
