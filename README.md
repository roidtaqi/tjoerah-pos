# Tjoerah POS

Tjoerah POS adalah aplikasi point of sale dengan API Laravel dan klien Flutter.
Repository ini dikonfigurasi untuk pengembangan dan demonstrasi lokal.

## Struktur

- `tjoerah-backend`: REST API Laravel dan database SQLite lokal.
- `tjoerah_mobile`: aplikasi Flutter untuk Android, desktop, dan web.
- `docs/architecture`: dokumentasi arsitektur aplikasi.

## Menjalankan Backend

Persyaratan: PHP 8.2 atau lebih baru, Composer, dan ekstensi SQLite.

```bash
cd tjoerah-backend
composer install
cp .env.example .env
php artisan key:generate
php artisan jwt:secret
touch database/database.sqlite
php artisan migrate:fresh --seed
php artisan serve --host=0.0.0.0 --port=8000
```

API tersedia di `http://127.0.0.1:8000/api` dan pemeriksaan kesehatan di
`http://127.0.0.1:8000/up`.

## Menjalankan Flutter

Untuk Chrome pada komputer yang sama:

```bash
cd tjoerah_mobile
flutter pub get
flutter run -d chrome
```

Untuk perangkat Android melalui USB, teruskan port backend terlebih dahulu:

```bash
adb reverse tcp:8000 tcp:8000
cd tjoerah_mobile
flutter run
```

Android Emulator dapat memakai URL host emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Backend juga dapat dijalankan sebagai Docker Web Service di Render. Gunakan
konfigurasi dan environment variable pada
[`tjoerah-backend/README.md`](tjoerah-backend/README.md#deploy-ke-render).

## Akun Demo

| Role | Email | Password | PIN |
| --- | --- | --- | --- |
| Owner | `owner@tjoerah.com` | `password` | `1234` |
| Cashier | `cashier@tjoerah.com` | `password` | `5678` |

Data demo dibuat oleh `php artisan migrate:fresh --seed`.

## Pengujian

```bash
cd tjoerah-backend && php artisan test
cd ../tjoerah_mobile && flutter analyze && flutter test
```
