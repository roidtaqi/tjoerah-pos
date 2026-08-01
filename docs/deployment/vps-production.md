# Tjoerah POS on a VPS

Target awal yang disarankan untuk dua outlet dan sekitar 20 perangkat aktif:

- 2 vCPU, RAM 4 GB, NVMe 40 GB atau lebih
- Ubuntu LTS, Nginx, PHP 8.4 FPM, Supervisor, dan Certbot
- PostgreSQL terkelola di region terdekat, idealnya Singapura
- HTTPS wajib; sertifikat Let's Encrypt sudah cukup

## Proses aplikasi

Jalankan tiga proses berikut:

1. Nginx dan PHP-FPM untuk API Laravel.
2. `php artisan reverb:start` untuk pembaruan KDS realtime.
3. `php artisan queue:work` melalui Supervisor.

Salin dan sesuaikan template dari `tjoerah-backend/deployment/vps`. Ganti
`api.example.com`, lokasi proyek, dan socket PHP-FPM sebelum mengaktifkannya.

Tambahkan scheduler Laravel ke crontab pengguna `www-data`:

```cron
* * * * * cd /var/www/tjoerah-pos/tjoerah-backend && php artisan schedule:run >> /dev/null 2>&1
```

Scheduler ini juga membersihkan foto absensi yang melewati masa retensi.

## Deploy backend

```bash
composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
php artisan migrate --force
php artisan optimize
sudo supervisorctl restart tjoerah-queue tjoerah-reverb
sudo systemctl reload php8.4-fpm nginx
```

Sesudah mengubah `.env`, selalu jalankan kembali `php artisan optimize` dan
restart proses Supervisor. Jangan jalankan `php artisan serve` di produksi.

## Build aplikasi

`REVERB_APP_KEY` adalah identifier publik dan boleh disertakan saat build.
`REVERB_APP_SECRET`, `APP_KEY`, `JWT_SECRET`, dan kredensial database tidak
boleh dimasukkan ke Flutter.

```bash
flutter build apk --release \
  --dart-define="API_BASE_URL=https://api.example.com/api" \
  --dart-define="REALTIME_ENABLED=true" \
  --dart-define="REVERB_APP_KEY=your-public-reverb-key" \
  --dart-define="REVERB_HOST=api.example.com" \
  --dart-define="REVERB_PORT=443" \
  --dart-define="REVERB_SCHEME=https"
```

## Foto absensi

Aplikasi mengecilkan foto menjadi JPEG tanpa metadata EXIF sebelum unggah,
dengan batas backend 1 MB. Disk lokal dapat dipakai saat peluncuran, tetapi
harus masuk backup harian. Untuk retensi panjang, isi konfigurasi S3-compatible
di `.env` lalu gunakan `ATTENDANCE_FILESYSTEM_DISK=s3`; endpoint foto tetap
privat dan memeriksa hak akses pengguna.

Pantau pemakaian RAM, CPU, disk, waktu respons p95, error 5xx, dan jumlah
koneksi Reverb selama dua minggu pertama. Naik ke 4 vCPU hanya jika CPU sering
di atas 70 persen atau p95 tetap tinggi setelah query/database diperiksa.
