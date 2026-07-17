FROM php:8.4-cli-alpine

RUN apk add --no-cache \
        git \
        libpq \
        unzip \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        postgresql-dev \
    && docker-php-ext-install -j"$(nproc)" pdo_pgsql \
    && apk del .build-deps

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN addgroup -S app && adduser -S -G app app

WORKDIR /var/www/html

RUN chown app:app /var/www/html

COPY --chown=app:app \
    tjoerah-backend/composer.json \
    tjoerah-backend/composer.lock \
    ./

USER app

RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --no-scripts \
    --no-autoloader

COPY --chown=app:app tjoerah-backend/ ./

RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --optimize-autoloader \
    && mkdir -p \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache

ENV APP_NAME="Tjoerah POS" \
    APP_ENV=production \
    APP_DEBUG=false \
    APP_LOCALE=id \
    APP_FALLBACK_LOCALE=id \
    APP_FAKER_LOCALE=id_ID \
    LOG_CHANNEL=stderr \
    LOG_LEVEL=info \
    DB_CONNECTION=pgsql \
    DB_SSLMODE=require \
    SESSION_DRIVER=cookie \
    CACHE_STORE=database \
    QUEUE_CONNECTION=sync \
    BROADCAST_CONNECTION=log \
    FILESYSTEM_DISK=local \
    JWT_TTL=480 \
    CORS_ALLOWED_ORIGINS=https://roidtaqi.github.io,http://localhost:3000,http://127.0.0.1:3000 \
    SEED_DEMO_DATA=true \
    PORT=8080 \
    PHP_CLI_SERVER_WORKERS=1

EXPOSE 8080

CMD ["sh", "cloud/start.sh"]
