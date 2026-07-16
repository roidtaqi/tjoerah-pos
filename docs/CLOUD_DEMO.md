# Tjoerah POS Cloud Demo

Arsitektur demo gratis yang dipakai:

```text
Flutter pada ponsel atau Chrome
        |
        v
Laravel API pada situs PHP alwaysdata Free
        |
        v
PostgreSQL terkelola pada akun alwaysdata yang sama
```

Komputer lokal tidak perlu menjalankan Laravel atau PostgreSQL. Setelah domain
alwaysdata menjadi URL API bawaan Flutter, demonstrasi di perangkat cukup
dimulai dengan:

```bash
cd tjoerah_mobile
flutter run
```

## Batas Penggunaan

Paket alwaysdata Free tidak meminta kartu kredit dan tidak memiliki batas
waktu. Paket ini menyediakan domain `alwaysdata.net`, PHP, Composer, SSH,
PostgreSQL, penyimpanan 1 GB, dan RAM 256 MB.

Paket Free ditujukan untuk penggunaan personal. Deployment ini hanya digunakan
sebagai prototipe dan presentasi, bukan operasional bisnis atau penyimpanan data
klien. Sebelum aplikasi dipakai dalam bisnis, pindahkan ke paket atau penyedia
produksi dengan kapasitas, ketentuan penggunaan, dan SLA yang sesuai.

## 1. Buat Akun Free

1. Buka <https://www.alwaysdata.com/en/register/>.
2. Pilih paket **Free** dan selesaikan verifikasi e-mail.
3. Catat nama akun. Domain permanennya berbentuk
   `https://NAMA_AKUN.alwaysdata.net`.

Akun Free biasanya sudah memiliki pengguna SSH serta database dan pengguna
PostgreSQL awal. Detail yang tepat selalu tersedia pada panel administrasi.

## 2. Siapkan PostgreSQL

Buka **Databases > PostgreSQL**. Gunakan database dan pengguna awal atau buat
keduanya khusus untuk Tjoerah POS. Catat nilai berikut tanpa menyimpannya di
Git:

```text
Host: postgresql-NAMA_AKUN.alwaysdata.net
Port: 5432
Database: NAMA_DATABASE
Username: NAMA_PENGGUNA_DATABASE
Password: PASSWORD_DATABASE
```

Database berada di cloud dan tidak bergantung pada komputer pengembangan.

## 3. Pasang Backend melalui SSH

Atur **Environment > PHP** ke PHP 8.4. Aktifkan SSH pada **Remote access >
SSH/SFTP**, lalu hubungkan terminal ke:

```bash
ssh NAMA_AKUN@ssh-NAMA_AKUN.alwaysdata.net
```

Pada server alwaysdata, jalankan:

```bash
git clone --branch agent/northflank-cloud-demo \
  https://github.com/roidtaqi/tjoerah-pos.git
cd tjoerah-pos/tjoerah-backend
cp .env.alwaysdata.example .env
```

Edit `.env` hanya di server. Ganti `YOUR_ACCOUNT`, URL aplikasi, dan seluruh
nilai database. Jangan mengirim atau melakukan commit terhadap file `.env`.

Setelah konfigurasi terisi, jalankan:

```bash
sh cloud/deploy-shared-hosting.sh
```

Skrip tersebut memasang dependency produksi, membuat `APP_KEY` dan
`JWT_SECRET` bila masih kosong, menjalankan migrasi, menanam data demo secara
idempoten, dan membuat cache produksi Laravel.

## 4. Arahkan Situs ke Laravel

Buka **Web > Sites** dan ubah situs domain akun dengan konfigurasi:

```text
Type: PHP
Address: NAMA_AKUN.alwaysdata.net
Root directory: /home/NAMA_AKUN/tjoerah-pos/tjoerah-backend/public
PHP version: 8.4
HTTPS redirect: enabled
```

Laravel sudah memiliki `public/.htaccess` untuk meneruskan route API ke front
controller. Uji deployment melalui:

```text
https://NAMA_AKUN.alwaysdata.net/up
```

## 5. Hubungkan Flutter

Setelah health check dan login cloud berhasil, jadikan URL berikut sebagai nilai
bawaan `API_BASE_URL` di Flutter:

```text
https://NAMA_AKUN.alwaysdata.net/api
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
3. Buat satu transaksi tunai, lalu pastikan pesanan tidak berstatus menunggu
   sinkron.
4. Jalankan `flutter run` pada perangkat presentasi.

Referensi resmi:

- <https://www.alwaysdata.com/en/offers/>
- <https://help.alwaysdata.com/en/docs/web-hosting/languages/php/packages/>
- <https://help.alwaysdata.com/en/docs/web-hosting/databases/postgresql/>
- <https://help.alwaysdata.com/en/docs/web-hosting/remote-access/ssh/>
- <https://help.alwaysdata.com/en/docs/web-hosting/sites/add-a-site/>
