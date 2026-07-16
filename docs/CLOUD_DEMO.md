# Tjoerah POS Cloud Demo

Arsitektur demo gratis:

- Flutter Web: GitHub Pages
- Laravel API: Koyeb Free Web Service
- PostgreSQL: Neon Free

Frontend dan database tetap tersedia tanpa komputer lokal. Koyeb Free tidur
setelah satu jam tanpa trafik dan bangun otomatis saat menerima request baru.
Biasanya cold start memerlukan 1-5 detik. Buka endpoint `/up` sebelum presentasi
untuk memastikan API sudah hangat.

## 0. Publikasikan Source Code

Koyeb dan GitHub Actions membaca repository GitHub, bukan perubahan yang masih
berada di komputer lokal. Periksa, commit, lalu push seluruh perubahan yang akan
dipresentasikan:

```bash
git status
git add .github docs tjoerah-backend tjoerah_mobile
git commit -m "Prepare Tjoerah POS cloud demo"
git push origin main
```

## 1. Buat Database Neon

1. Buat akun di <https://console.neon.tech>.
2. Buat project `tjoerah-pos` di region AWS Europe (Frankfurt).
3. Salin connection string PostgreSQL yang menggunakan SSL.
4. Simpan connection string tersebut. Jangan masukkan ke Git.

Paket Neon Free tidak memiliki batas waktu, menyediakan 0,5 GB storage, dan
compute akan tidur ketika tidak digunakan.

## 2. Buat Secret

Jalankan perintah berikut dari folder `tjoerah-backend`:

```bash
php artisan key:generate --show
openssl rand -hex 48
```

Nilai pertama digunakan sebagai `APP_KEY`. Nilai kedua digunakan sebagai
`JWT_SECRET`.

Di Koyeb, buka **Secrets** dan buat:

```text
TJOERAH_APP_KEY=<hasil php artisan key:generate --show>
TJOERAH_JWT_SECRET=<hasil openssl rand -hex 48>
NEON_DATABASE_URL=<connection string Neon>
```

## 3. Deploy Laravel ke Koyeb

1. Masuk ke <https://app.koyeb.com> menggunakan GitHub.
2. Pilih **Create Web Service**, lalu repository `roidtaqi/tjoerah-pos`.
3. Pilih branch `main` dan builder **Buildpack**.
4. Set work directory menjadi `tjoerah-backend`.
5. Pilih instance **Free** dan region **Frankfurt**.
6. Expose port `8000` menggunakan HTTP pada path `/`.
7. Set health check HTTP ke path `/up` pada port `8000`.
8. Masukkan environment berikut melalui **Bulk Edit**:

```text
APP_NAME=Tjoerah POS
APP_ENV=production
APP_KEY={{ secret.TJOERAH_APP_KEY }}
APP_DEBUG=false
APP_URL=https://{{ KOYEB_PUBLIC_DOMAIN }}
APP_LOCALE=id
APP_FALLBACK_LOCALE=id
LOG_CHANNEL=stderr
LOG_LEVEL=info
DB_CONNECTION=pgsql
DB_URL={{ secret.NEON_DATABASE_URL }}
DB_SSLMODE=require
SESSION_DRIVER=cookie
CACHE_STORE=database
QUEUE_CONNECTION=sync
BROADCAST_CONNECTION=log
FILESYSTEM_DISK=local
JWT_SECRET={{ secret.TJOERAH_JWT_SECRET }}
JWT_TTL=480
CORS_ALLOWED_ORIGINS=https://roidtaqi.github.io,http://localhost:3000,http://127.0.0.1:3000
SEED_DEMO_DATA=true
```

Deployment menjalankan migrasi dan seeder secara otomatis. Seeder aman untuk
dijalankan ulang dan tidak mengubah password akun yang sudah ada.

Setelah status service menjadi **Healthy**, buka:

```text
https://<domain-koyeb>/up
```

## 4. Hubungkan Flutter Web

Set repository variable GitHub menggunakan URL Koyeb:

```bash
gh variable set API_BASE_URL --body "https://<domain-koyeb>/api"
```

Di GitHub, buka **Settings > Pages** dan pilih **GitHub Actions** sebagai source.
Kemudian jalankan workflow:

```bash
gh workflow run deploy-web.yml
```

Frontend akan tersedia di:

```text
https://roidtaqi.github.io/tjoerah-pos/
```

## 5. Akun Demo

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

## Menjalankan Web Lokal dengan API Cloud

Server Laravel lokal tidak diperlukan. Gunakan URL Koyeb saat menjalankan
Flutter di Chrome:

```bash
flutter run -d chrome \
  --web-port 3000 \
  --dart-define=API_BASE_URL=https://<domain-koyeb>/api
```

## Batas Paket Gratis

Koyeb Free menyediakan 512 MB RAM dan akan tidur setelah satu jam tanpa trafik.
Data tidak hilang karena PostgreSQL berada di Neon. Untuk server yang benar-benar
tidak pernah tidur, gunakan Oracle Cloud Always Free atau Google Cloud Free Tier
`e2-micro`; keduanya memerlukan pengelolaan VM dan biasanya verifikasi billing.

Referensi resmi:

- <https://www.koyeb.com/docs/reference/instances>
- <https://www.koyeb.com/docs/run-and-scale/scale-to-zero>
- <https://neon.com/pricing>
- <https://docs.github.com/pages>
