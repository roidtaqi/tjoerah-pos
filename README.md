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

Dengan USB, aplikasi dapat tetap memakai API bawaan
`http://127.0.0.1:8000/api`. Periksa koneksi perangkat dengan `adb devices`.

Untuk perangkat Android pada jaringan Wi-Fi yang sama, cari IP laptop:

```bash
hostname -I
```

Lalu jalankan Flutter dengan IP tersebut, misalnya:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.113:8000/api
```

Android Emulator dapat memakai URL host emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

## Deploy Backend ke Railway

Repository ini mendukung Railway Railpack tanpa Dockerfile.

1. Buat project dari repository GitHub `roidtaqi/tjoerah-pos`.
2. Pada service Laravel, atur Root Directory menjadi `/tjoerah-backend`.
3. Tambahkan variable berikut melalui Raw Editor. Gunakan hasil
   `php artisan key:generate --show` dan `php artisan jwt:secret --show` untuk
   kedua secret tersebut.

```dotenv
APP_NAME=Tjoerah POS
APP_ENV=production
APP_KEY=base64:HASIL_KEY_GENERATE
APP_DEBUG=false
APP_URL=http://localhost
APP_LOCALE=id
APP_FALLBACK_LOCALE=id
LOG_CHANNEL=stderr
LOG_LEVEL=info
DB_CONNECTION=pgsql
DB_URL=POSTGRESQL_URL_DARI_NEON
SESSION_DRIVER=database
CACHE_STORE=database
QUEUE_CONNECTION=database
FILESYSTEM_DISK=local
JWT_SECRET=HASIL_JWT_SECRET
JWT_TTL=480
CORS_ALLOWED_ORIGINS=*
SEED_DEMO_DATA=true
DEMO_OWNER_PASSWORD=PASSWORD_OWNER_YANG_KUAT
DEMO_OWNER_PIN=PIN_OWNER_BARU
DEMO_CASHIER_PASSWORD=PASSWORD_KASIR_YANG_KUAT
DEMO_CASHIER_PIN=PIN_KASIR_BARU
```

4. Deploy service. Migrasi dan seed demo dijalankan otomatis sebelum versi
   baru diaktifkan.
5. Buka `Settings > Networking`, pilih `Generate Domain`, lalu pastikan
   `https://DOMAIN_RAILWAY/up` menghasilkan status `200`.
   Setelah domain tersedia, ubah `APP_URL` menjadi URL Railway lengkap,
   misalnya `https://tjoerah-pos-production.up.railway.app`, tanpa `/api`.
6. Agar foto absensi tidak hilang saat redeploy, tambahkan volume ke service
   dengan mount path `/data`, lalu tambahkan variable
   `LOCAL_FILESYSTEM_ROOT=/data`.
7. Setelah database demo terisi, ubah `SEED_DEMO_DATA=false`.

Jalankan aplikasi Android terhadap backend Railway:

```bash
flutter run --dart-define=API_BASE_URL=https://DOMAIN_RAILWAY/api
```

## Akun Demo

| Role | Email | Password | PIN |
| --- | --- | --- | --- |
| Owner | `owner@tjoerah.com` | `password` | `1234` |
| Cashier | `cashier@tjoerah.com` | `password` | `5678` |

Data demo dibuat oleh `php artisan migrate:fresh --seed`.

## Absensi Karyawan

- Semua role membuka `Lainnya > Absensi saya` untuk absen masuk atau pulang.
- Owner dan admin membuka `Lainnya > Manajemen absensi` untuk laporan,
  jadwal, kebijakan keterlambatan, geofence, pemeriksaan foto, koreksi, dan
  ekspor CSV.
- Waktu resmi dicatat oleh server. Foto disimpan privat dan hanya dapat dibuka
  oleh karyawan terkait atau owner/admin pada tenant yang sama.
- Untuk database lokal yang sudah ada, jalankan `php artisan migrate` lalu
  `php artisan db:seed`.
- Di server produksi, jalankan Laravel scheduler agar foto melewati masa
  retensinya dapat dibersihkan otomatis:

```bash
php artisan schedule:work
```

## Pengujian

```bash
cd tjoerah-backend && php artisan test
cd ../tjoerah_mobile && flutter analyze && flutter test
```
