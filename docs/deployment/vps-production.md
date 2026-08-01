# Tjoerah POS on a VPS

Target minimum berbiaya rendah untuk dua outlet dan sekitar 20 perangkat aktif:

- 1 vCPU, RAM 1 GB, SSD 20 GB atau lebih
- Gunakan `php-fpm-pool-1gb.conf.example` dan
  `php-opcache-1gb.ini.example`
- Batasi foto lokal ke retensi 30 hari atau gunakan object storage

Target yang lebih longgar untuk beban yang sama:

- 2 vCPU, RAM 2 GB, SSD 40 GB atau lebih
- Ubuntu 26.04 LTS, Nginx, PHP 8.5 FPM, Supervisor, dan Certbot
- PostgreSQL terkelola di region terdekat, idealnya Singapura
- HTTPS wajib; sertifikat Let's Encrypt sudah cukup

Profil 1 GB adalah batas minimum dan harus diuji setelah VPS aktif. Profil 2 GB
lebih aman untuk transaksi bersamaan, sedangkan RAM 4 GB memberi ruang lebih
longgar tanpa perlu memantau server secara rutin.

## Proses aplikasi

Jalankan dua kelompok proses berikut:

1. Nginx dan PHP-FPM untuk API Laravel.
2. `php artisan reverb:start` untuk pembaruan KDS realtime.

Backend saat ini tidak memiliki job asynchronous dan event KDS memakai
`ShouldBroadcastNow`. Karena itu `.env.production.example` menggunakan
`QUEUE_CONNECTION=sync` dan tidak menjalankan queue worker. Tambahkan satu
worker hanya setelah aplikasi benar-benar memiliki queued job.

Salin dan sesuaikan template dari `tjoerah-backend/deployment/vps`. Ganti
`api.example.com`, lokasi proyek, dan socket PHP-FPM sebelum mengaktifkannya.
Untuk VPS RAM 1 GB atau 2 GB, terapkan template PHP-FPM yang sesuai agar worker
hanya dibuat ketika ada request dan berhenti kembali saat idle. Jangan memasang
Docker, database, Redis, atau control panel pada VPS 1 GB.

Tambahkan swap 2 GB sebagai pengaman lonjakan memori:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-tjoerah.conf
sudo sysctl --system
```

Swap tidak boleh menjadi memori utama. Jika pemakaiannya terus bertambah saat
jam sibuk, naikkan paket ke RAM 4 GB.

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
sudo supervisorctl restart tjoerah-reverb
sudo systemctl reload php8.5-fpm nginx
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
dengan batas backend 1 MB. Disk lokal 20 GB hanya layak dengan retensi foto 30
hari dan backup harian. Untuk retensi lebih panjang, isi konfigurasi
S3-compatible di `.env` lalu gunakan `ATTENDANCE_FILESYSTEM_DISK=s3`; endpoint
foto tetap privat dan memeriksa hak akses pengguna.

Pantau pemakaian RAM, CPU, disk, waktu respons p95, error 5xx, dan jumlah
koneksi Reverb selama dua minggu pertama. Pada VPS 1 GB, naik ke paket 2 vCPU
dan RAM 2 GB jika CPU sering di atas 70 persen, swap terus berada di atas 256
MB, proses dihentikan karena kehabisan memori, atau p95 transaksi melewati 800
ms setelah latensi database diperiksa.
