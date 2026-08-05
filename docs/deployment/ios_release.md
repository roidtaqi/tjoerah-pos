# Rilis iOS Tjoerah POS

## Baseline

- Minimum iOS: 13.1.
- Target: iPhone dan iPad.
- API produksi bawaan: `https://api.tjoerahpos.com/api`.
- Kamera dipakai tanpa audio untuk foto absensi.
- Lokasi hanya diminta saat aplikasi digunakan.
- Printer thermal didukung melalui Bluetooth Low Energy (BLE) di iOS.

## Persiapan di Mac

1. Pasang Xcode 15 atau lebih baru yang didukung oleh versi Flutter proyek.
2. Masuk ke Xcode menggunakan akun Apple Developer aktif.
3. Jalankan:

   ```bash
   cd tjoerah_mobile
   flutter doctor -v
   flutter clean
   flutter pub get
   open ios/Runner.xcworkspace
   ```

4. Di Xcode, buka target **Runner** lalu **Signing & Capabilities**.
5. Pilih Apple Developer Team dan pertahankan **Automatically manage signing**.
6. Pastikan Bundle Identifier `com.tjoerah.tjoerahMobile` tersedia pada akun tersebut. Ganti hanya jika identifier itu sudah dimiliki aplikasi lain.
7. Pilih iPhone atau iPad fisik, lalu jalankan target Runner.

Flutter akan membangkitkan integrasi Swift Package Manager untuk plugin native saat build pertama di Mac. Jangan mengubah isi `ios/Flutter/ephemeral` secara manual.

## Verifikasi Perangkat

- Login email/telepon/username dan PIN.
- Kamera depan/belakang, izin lokasi, dan alur absensi.
- Sinkronisasi POS ke `https://api.tjoerahpos.com/api`.
- Printer kasir, dapur, dan bar secara terpisah.
- Dua printer dengan nama sama tetap dipilih berdasarkan ID perangkat yang berbeda.
- Cetak struk, tiket produksi, cetak ulang, open bill, dan laporan shift.
- Rotasi serta layout pada iPhone dan iPad.

Printer Bluetooth Classic SPP murah yang hanya kompatibel dengan Android tidak dapat dipakai oleh iPhone. Printer untuk iOS harus menyediakan BLE dengan karakteristik tulis yang kompatibel ESC/POS, atau memiliki sertifikasi MFi.

## Arsip Produksi

Setelah pengujian perangkat fisik lulus:

```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.tjoerahpos.com/api
```

Unggah arsip melalui Xcode Organizer atau aplikasi Transporter. Lengkapi privacy details App Store Connect untuk kamera, lokasi presisi, identifier pengguna, data transaksi, dan foto absensi sesuai pemakaian aplikasi.
