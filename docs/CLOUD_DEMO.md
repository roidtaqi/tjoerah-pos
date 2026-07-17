# Tjoerah POS Cloud Demo

Arsitektur demo berbiaya rendah:

```text
Flutter pada ponsel atau Chrome
        |
        v
Laravel API pada Helipod
        |
        v
PostgreSQL pada Neon Free
```

Komputer lokal tidak perlu menjalankan Laravel atau PostgreSQL. Setelah domain
Helipod menjadi URL API bawaan Flutter, demonstrasi di perangkat cukup dimulai
dengan:

```bash
cd tjoerah_mobile
flutter run
```

## Biaya dan Batas Penggunaan

Gunakan preset **Chopper** dengan 0,25 vCPU, RAM 256 MB, satu replica, dan tanpa
custom domain. Biayanya Rp700 per hari atau sekitar Rp21.000 untuk 30 hari.
Domain `*.helipod.app`, HTTPS, internal networking, dan 1 GB storage sudah
tersedia tanpa membeli domain sendiri.

Database tetap menggunakan project Neon Free yang sudah dibuat sehingga tidak
ada biaya pod database tambahan dan redeploy aplikasi tidak menghapus data.

Helipod adalah platform milik penyedia Indonesia dan menerima QRIS, transfer
bank, serta virtual account. Infrastruktur komputasinya saat ini berada di luar
Indonesia; deployment ini ditujukan untuk demo dan validasi awal, bukan sebagai
keputusan final data residency atau produksi klien.

## 1. Buat Akun Helipod

1. Buka <https://helipod.io/> dan pilih **Mulai Gratis**.
2. Masuk menggunakan GitHub agar repository dapat dihubungkan langsung.
3. Jangan melakukan top-up sebelum deployment percobaan berhasil.

## 2. Buat Project dari GitHub

Pilih **New Project > GitHub**, kemudian gunakan konfigurasi:

```text
Repository: roidtaqi/tjoerah-pos
Branch: agent/northflank-cloud-demo
Working directory: tjoerah-backend
Build method: Dockerfile
Preset: Chopper (0.25 vCPU, 256 MB RAM)
Replicas: 1
Custom domain: disabled
```

Helipod mendukung working directory per service untuk repository monorepo dan
akan menggunakan `tjoerah-backend/Dockerfile` sebagai proses build.

## 3. Tambahkan Rahasia

Sebelum deploy, buka **Variables** dan tambahkan:

```text
APP_KEY_BASE64=<base64 key 32 byte>
DB_URL=<pooled connection string Neon>
JWT_SECRET=<random secret>
```

Jangan menyimpan ketiga nilai tersebut di Git atau mengirimkannya melalui
tangkapan layar. Nilai lain seperti PostgreSQL, SSL database, logging, queue
sinkron, seeder demo, dan port 8080 sudah menjadi default image.

## 4. Deploy dan Verifikasi

Klik **Deploy**. Saat container dimulai, backend otomatis:

1. Menjalankan migrasi database dengan retry.
2. Menanam akun dan katalog demo secara idempoten.
3. Membuat cache konfigurasi produksi.
4. Menjalankan server HTTP pada port yang disediakan platform.

Setelah status menjadi **Running**, salin magic domain yang diberikan dan uji:

```text
https://NAMA-SERVICE.helipod.app/up
```

## 5. Hubungkan Flutter

Setelah health check, login, dan transaksi cloud berhasil, jadikan URL berikut
sebagai nilai bawaan Flutter:

```text
https://NAMA-SERVICE.helipod.app/api
```

URL lain tetap dapat diuji tanpa mengubah kode:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://api-lain.example/api
```

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

`1234` dan `5678` adalah PIN untuk login PIN, bukan password login e-mail.

## Sebelum Presentasi

1. Buka endpoint `/up` dan pastikan respons berhasil.
2. Uji login e-mail Owner dan login PIN Kasir.
3. Buat satu transaksi tunai dan pastikan pesanan berhasil disinkronkan.
4. Jalankan `flutter run` pada perangkat presentasi.

Referensi resmi:

- <https://helipod.io/pricing>
- <https://helipod.io/feature/dockerfile-support>
- <https://helipod.io/feature/environment-variables>
- <https://docs.helipod.io/quick-start>
- <https://neon.com/pricing>
