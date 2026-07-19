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

## Deploy ke Render

Gunakan **New Web Service** dengan pengaturan berikut:

| Field | Nilai |
| --- | --- |
| Language | `Docker` |
| Branch | `main` |
| Region | `Singapore` |
| Root Directory | `tjoerah-backend` |
| Dockerfile Path | `./Dockerfile` |
| Health Check Path | `/up` |

Paket `Free` cukup untuk demonstrasi. Layanan gratis akan berhenti sementara
setelah tidak menerima trafik dan memerlukan waktu untuk aktif kembali.

Buat dua secret dari terminal lokal tanpa membagikan hasilnya:

```bash
php artisan key:generate --show
php artisan jwt:secret --show
```

Masukkan environment variable dari [`render.env.example`](render.env.example)
ke dashboard Render. Ganti nilai `APP_KEY`, `JWT_SECRET`, dan `DB_URL` dengan
nilai sebenarnya. `DB_URL` harus berisi connection string PostgreSQL Neon dan
`APP_KEY` harus menyertakan awalan `base64:`.

Saat container dimulai, aplikasi otomatis menjalankan migrasi. Jika
`SEED_DEMO_DATA=true`, data akun dan produk demo juga diisi secara idempoten.
Setelah deployment selesai, periksa:

```text
https://NAMA-SERVICE.onrender.com/up
```

Respons sukses dari endpoint tersebut menandakan API siap digunakan.

Panduan lengkap aplikasi tersedia di [`README.md`](../README.md).
