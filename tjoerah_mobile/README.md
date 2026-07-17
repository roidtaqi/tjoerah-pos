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

## Pemeriksaan

```bash
flutter analyze
flutter test
```

Panduan lengkap aplikasi tersedia di [`README.md`](../README.md).
