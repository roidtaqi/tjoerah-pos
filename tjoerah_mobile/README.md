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

1. Pasangkan printer thermal dari pengaturan Bluetooth Android.
2. Buka **Lainnya > Printer transaksi** di aplikasi.
3. Izinkan akses perangkat sekitar dan lokasi ketika diminta.
4. Pilih printer, tekan **Hubungkan**, lalu jalankan **Cetak tes**.

Printer terakhir akan disambungkan kembali secara otomatis. Setelah pembayaran
berhasil, aplikasi mencetak struk pelanggan dan tiket produksi per stasiun.
Dialog transaksi juga menyediakan tombol cetak ulang untuk **Struk** atau
**Dapur** secara terpisah.

## Pemeriksaan

```bash
flutter analyze
flutter test
```

Panduan lengkap aplikasi tersedia di [`README.md`](../README.md).
