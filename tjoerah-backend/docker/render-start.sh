#!/bin/sh
set -eu

echo "Preparing Tjoerah POS backend..."

php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan migrate --force

if [ "${SEED_DEMO_DATA:-false}" = "true" ]; then
    php artisan db:seed --force
fi

php artisan config:cache

echo "Starting HTTP server on port ${PORT:-10000}..."
exec php artisan serve --host=0.0.0.0 --port="${PORT:-10000}"
