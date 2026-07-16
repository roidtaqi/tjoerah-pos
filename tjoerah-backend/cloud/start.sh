#!/bin/sh

set -eu

if [ -z "${APP_KEY:-}" ] && [ -n "${APP_KEY_BASE64:-}" ]; then
    export APP_KEY="base64:${APP_KEY_BASE64}"
fi

if [ -z "${APP_KEY:-}" ]; then
    echo "APP_KEY or APP_KEY_BASE64 must be configured." >&2
    exit 1
fi

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

exec php artisan serve --host=0.0.0.0 --port="${PORT:-8080}"
