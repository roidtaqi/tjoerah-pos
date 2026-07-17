# Tjoerah POS Backend

REST API Laravel untuk autentikasi, POS, meja, pesanan, inventori, resep,
pelanggan, KDS, dan laporan Tjoerah POS.

## Setup Lokal

```bash
composer install
cp .env.example .env
php artisan key:generate
php artisan jwt:secret
touch database/database.sqlite
php artisan migrate:fresh --seed
php artisan serve --host=0.0.0.0 --port=8000
```

Jalankan pengujian dengan:

```bash
php artisan test
```

Panduan lengkap aplikasi tersedia di [`README.md`](../README.md).
