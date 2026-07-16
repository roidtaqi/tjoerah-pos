#!/bin/sh

set -eu

attempt=1
max_attempts=10

until php artisan migrate --force; do
    if [ "$attempt" -ge "$max_attempts" ]; then
        echo "Database migration failed after $max_attempts attempts." >&2
        exit 1
    fi

    echo "Database is not ready; retrying migration ($attempt/$max_attempts)..." >&2
    attempt=$((attempt + 1))
    sleep 3
done

if [ "${SEED_DEMO_DATA:-false}" = "true" ]; then
    php artisan db:seed --force
fi

php artisan optimize

if command -v heroku-php-nginx >/dev/null 2>&1; then
    exec heroku-php-nginx public/
fi

exec php artisan serve --host=0.0.0.0 --port="${PORT:-8000}"
