#!/bin/sh

set -eu

if [ ! -f .env ]; then
    echo "Missing .env. Copy the hosting template and fill in the database settings first." >&2
    exit 1
fi

composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --optimize-autoloader

mkdir -p \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache

chmod -R u+rwX storage bootstrap/cache

if ! grep -Eq '^APP_KEY=.+$' .env; then
    php artisan key:generate --force
fi

if ! grep -Eq '^JWT_SECRET=.+$' .env; then
    php artisan jwt:secret --force
fi

php artisan config:clear
php artisan migrate --force

if grep -Eq '^SEED_DEMO_DATA=true$' .env; then
    php artisan db:seed --force
fi

php artisan optimize

echo "Tjoerah POS backend deployment is ready."
