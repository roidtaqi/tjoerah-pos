# Tjoerah POS Mobile

Klien Flutter untuk operasional Tjoerah POS.

## Menjalankan

```bash
flutter pub get
flutter run
```

Secara default aplikasi memakai API lokal di `http://127.0.0.1:8000/api`.
Gunakan `adb reverse tcp:8000 tcp:8000` sebelum `flutter run` pada perangkat
Android melalui USB.

URL API lain dapat diberikan tanpa mengubah source code:

```bash
flutter run --dart-define=API_BASE_URL=http://HOST:8000/api
```

## Printer Bluetooth

1. Pasangkan semua printer thermal dari pengaturan Bluetooth Android.
2. Buka **Lainnya > Printer transaksi** di aplikasi.
3. Izinkan akses perangkat sekitar dan lokasi ketika diminta.
4. Tekan **Pindai**, lalu pilih perangkat untuk profil **Printer kasir**,
   **Printer dapur**, dan **Printer bar**.
5. Atur lebar kertas, jumlah salinan, cetak otomatis, dan pemotong kertas pada
   setiap profil, lalu jalankan **Cetak tes**.

Aplikasi menyambungkan printer tujuan secara berurutan ketika pekerjaan cetak
dijalankan, sehingga satu perangkat Android dapat memakai beberapa printer.
Tiket stasiun bar memakai printer bar; jika profil itu belum diatur, tiket akan
dialihkan ke printer dapur. Laporan shift selalu memakai printer kasir.

Setelah pembayaran berhasil, aplikasi dapat mencetak struk pelanggan dan tiket
produksi secara otomatis. Buka detail transaksi dari **Pesanan** untuk mencetak
ulang **Struk pelanggan**, **Tiket dapur**, atau semua dokumen. Hasil cetak ulang
diberi penanda salinan agar tidak tertukar dengan cetakan pertama.

## Pemeriksaan

```bash
flutter analyze
flutter test
```

Panduan lengkap aplikasi tersedia di [`README.md`](../README.md).
