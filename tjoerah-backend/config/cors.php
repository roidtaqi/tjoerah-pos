<?php

$configuredOrigins = (string) env('CORS_ALLOWED_ORIGINS', '*');
$allowedOrigins = $configuredOrigins === '*'
    ? ['*']
    : array_values(array_filter(array_map('trim', explode(',', $configuredOrigins))));

return [
    'paths' => ['api/*', 'up'],
    'allowed_methods' => ['*'],
    'allowed_origins' => $allowedOrigins,
    'allowed_origins_patterns' => [
        '#^https?://(localhost|127\.0\.0\.1)(:\d+)?$#',
    ],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 600,
    'supports_credentials' => false,
];
