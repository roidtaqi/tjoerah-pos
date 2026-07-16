# Tjoerah POS Cloud Demo

Arsitektur demo:

```text
Flutter pada ponsel atau Chrome
        |
        v
Laravel API di Northflank (selalu aktif)
        |
        v
PostgreSQL di Neon
```

Dengan arsitektur ini, komputer lokal tidak perlu menjalankan Laravel atau
PostgreSQL. Setelah URL API cloud dijadikan nilai bawaan aplikasi, demonstrasi
di perangkat cukup dimulai dengan:

```bash
cd tjoerah_mobile
flutter run
```

## 1. Database Neon

Project berikut sudah dibuat:

```text
Name: tjoerah-pos
Region: AWS Europe (Frankfurt)
Database: tjoerah_pos
```

Ambil pooled connection string dari menu **Connect** di Neon Console dan
pastikan URL berisi `sslmode=require`. Jangan memasukkannya ke Git.

## 2. Akun Northflank

1. Buka <https://app.northflank.com/signup> dan masuk menggunakan GitHub.
2. Pilih paket **Developer Sandbox**.
3. Buat project bernama `tjoerah-pos` di region Eropa yang tersedia.
4. Hubungkan akun GitHub jika diminta.

Developer Sandbox menyediakan layanan yang terus aktif tanpa tidur. Resource
gratis terkecil memiliki 0,1 shared vCPU dan RAM 256 MB, sehingga container ini
dibatasi menjadi satu PHP worker.

## 3. Buat Combined Service

Di dalam project `tjoerah-pos`, pilih **Create service > Combined service**:

```text
Name: tjoerah-pos-api
Repository: roidtaqi/tjoerah-pos
Branch: main
Build type: Dockerfile
Dockerfile path: /tjoerah-backend/Dockerfile
Build context: /tjoerah-backend
Deployment plan: Sandbox / nf-compute-10
Instances: 1
```

Aktifkan continuous deployment untuk branch `main`.

Tambahkan public port:

```text
Name: http
Protocol: HTTP
Internal port: 8080
Public: enabled
```

Tambahkan readiness health check:

```text
Protocol: HTTP
Path: /up
Port: 8080
Initial delay: 30 seconds
Period: 30 seconds
```

## 4. Runtime Variables

Buat dua nilai rahasia dari folder `tjoerah-backend`:

```bash
php -r 'echo base64_encode(random_bytes(32)), PHP_EOL;'
openssl rand -hex 48
```

Nilai pertama menjadi `APP_KEY_BASE64`; nilai kedua menjadi `JWT_SECRET`.
Masukkan runtime variables berikut melalui Northflank. Ganti nilai yang masih
menggunakan tanda `<...>`:

```text
APP_NAME=Tjoerah POS
APP_ENV=production
APP_KEY_BASE64=<hasil perintah pertama>
APP_DEBUG=false
APP_URL=https://<domain-code-run>
APP_LOCALE=id
APP_FALLBACK_LOCALE=id
LOG_CHANNEL=stderr
LOG_LEVEL=info
DB_CONNECTION=pgsql
DB_URL=<pooled connection string Neon>
DB_SSLMODE=require
SESSION_DRIVER=cookie
CACHE_STORE=database
QUEUE_CONNECTION=sync
BROADCAST_CONNECTION=log
FILESYSTEM_DISK=local
JWT_SECRET=<hasil perintah kedua>
JWT_TTL=480
CORS_ALLOWED_ORIGINS=https://roidtaqi.github.io,http://localhost:3000,http://127.0.0.1:3000
SEED_DEMO_DATA=true
PHP_CLI_SERVER_WORKERS=1
```

Container otomatis menjalankan migrasi, seeder akun demo, dan cache Laravel
setiap kali deployment dimulai. Seeder dapat dijalankan berulang kali tanpa
mengganti password akun yang sudah ada.

## 5. Hubungkan Flutter

Setelah deployment berstatus aktif, salin domain publik `code.run` dan periksa:

```text
https://<domain-code-run>/up
```

Sebelum URL tersebut dimasukkan sebagai nilai bawaan di `ApiClient`, aplikasi
dapat diuji tanpa backend lokal dengan:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://<domain-code-run>/api
```

Setelah nilai bawaan diperbarui dan aplikasi dibangun ulang, perintahnya menjadi
cukup `flutter run`.

## Akun Demo

```text
Owner
Email: owner@tjoerah.com
Password: password
PIN: 1234

Cashier
Email: cashier@tjoerah.com
Password: password
PIN: 5678
```

`1234` dan `5678` adalah PIN untuk login PIN, bukan password login email.

## Batas Paket Gratis

Developer Sandbox ditujukan untuk demo dan pengembangan, bukan operasional
produksi dengan SLA. Database tetap berada di Neon sehingga redeploy container
tidak menghapus transaksi. Jika kebutuhan client bertambah, service dapat
dipindahkan ke resource berbayar tanpa mengubah arsitektur aplikasi.

Referensi resmi:

- <https://northflank.com/pricing>
- <https://northflank.com/docs/v1/application/billing/pricing-on-northflank>
- <https://northflank.com/docs/v1/application/build/build-with-a-dockerfile>
- <https://northflank.com/docs/v1/application/network/expose-your-application>
- <https://neon.com/pricing>
