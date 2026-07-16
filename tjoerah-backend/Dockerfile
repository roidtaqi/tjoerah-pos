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

COPY --chown=app:app composer.json composer.lock ./

USER app

RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-progress \
    --no-scripts \
    --no-autoloader

COPY --chown=app:app . .

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

ENV PORT=8080 \
    PHP_CLI_SERVER_WORKERS=1

EXPOSE 8080

CMD ["sh", "cloud/start.sh"]
