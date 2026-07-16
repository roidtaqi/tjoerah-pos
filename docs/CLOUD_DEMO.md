# Tjoerah POS Cloud Demo

Arsitektur demo gratis:

```text
Flutter pada ponsel atau Chrome
        |
        v
Laravel API di Back4App Containers Free
        |
        v
PostgreSQL di Neon Free
```

Komputer lokal tidak perlu menjalankan Laravel atau PostgreSQL. Setelah domain
Back4App menjadi URL API bawaan Flutter, demonstrasi di perangkat cukup dimulai
dengan:

```bash
cd tjoerah_mobile
flutter run
```

## Karakteristik Paket Gratis

Back4App Containers Free tidak meminta kartu kredit. Paketnya menyediakan satu
container dengan 0,25 shared CPU, RAM 256 MB, transfer 100 GB, deployment dari
GitHub, dan domain `b4a.run`. Container backend Tjoerah memakai sekitar 64 MB
RAM pada pengujian lokal.

Database transaksi tetap berada di Neon sehingga redeploy container tidak
menghapus data.

## 1. Database Neon

Project berikut sudah dibuat:

```text
Project: tjoerah-pos
Region: AWS Europe (Frankfurt)
Database: tjoerah_pos
```

Ambil pooled connection string dari menu **Connect** di Neon Console. Pastikan
URL berisi `sslmode=require` dan jangan menyimpannya di Git.

## 2. Deploy Backend ke Back4App

1. Masuk ke <https://www.back4app.com/> menggunakan GitHub.
2. Pilih **Build new app**, lalu **Containers as a Service**.
3. Hubungkan GitHub dan pilih repository `roidtaqi/tjoerah-pos`.
4. Gunakan konfigurasi berikut:

```text
App name: tjoerah-pos-api
Branch: agent/northflank-cloud-demo
Root directory: tjoerah-backend
Plan: Free
Auto deploy: enabled
```

Dockerfile produksi sudah tersedia di root directory tersebut. Tambahkan tiga
environment variable rahasia berikut sebelum membuat app:

```text
APP_KEY_BASE64=<base64 key 32 byte>
DB_URL=<pooled connection string Neon>
JWT_SECRET=<random secret>
```

Buat dua nilai rahasia dari folder `tjoerah-backend`:

```bash
php -r 'echo base64_encode(random_bytes(32)), PHP_EOL;'
openssl rand -hex 48
```

Nilai pertama digunakan untuk `APP_KEY_BASE64` dan nilai kedua untuk
`JWT_SECRET`. Konfigurasi nonrahasia seperti PostgreSQL, SSL, logging, satu PHP
worker, dan seeder demo sudah menjadi default image.

Klik **Create App**. Container otomatis menjalankan migrasi, seeder akun demo,
cache Laravel, dan server HTTP. Seeder aman dijalankan berulang kali.

## 3. Hubungkan Flutter

Setelah deployment berstatus **Available**, buka domain dari **App Overview**
dan periksa:

```text
https://<service>.b4a.run/up
```

Tambahkan `APP_URL=https://<service>.b4a.run` pada environment variables setelah
domain diketahui, lalu deploy ulang.

Sebelum URL cloud dijadikan nilai bawaan aplikasi, pengujian dapat dilakukan
dengan:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://<service>.b4a.run/api
```

Setelah nilai bawaan `ApiClient` diperbarui dan aplikasi dibangun ulang,
perintahnya cukup `flutter run`.

## Akun Demo

```text
Owner
Email: owner@tjoerah.com
Password: password
PIN: 1234

Kasir
Email: cashier@tjoerah.com
Password: password
PIN: 5678
```

`1234` dan `5678` adalah PIN untuk login PIN, bukan password login email.

## Sebelum Presentasi

1. Buka `https://<service>.b4a.run/up` dan pastikan respons berhasil.
2. Jalankan `flutter run` dan lakukan satu login percobaan.
3. Gunakan akun Owner untuk mendemonstrasikan seluruh menu.

Paket gratis sesuai untuk demo dan pengembangan, bukan operasional produksi
dengan SLA. Matikan `SEED_DEMO_DATA` dan ganti seluruh kredensial sebelum
menggunakan deployment untuk data bisnis nyata.

Referensi resmi:

- <https://www.back4app.com/pricing/container-as-a-service>
- <https://www.back4app.com/docs-containers>
- <https://www.back4app.com/docs-containers/prepare-your-deployment>
- <https://neon.com/pricing>
