import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance_models.dart';

const _attendanceDeviceIdKey = 'attendance_device_id';

class AttendanceCaptureData {
  const AttendanceCaptureData({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isMock,
    required this.capturedAt,
    required this.deviceId,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool isMock;
  final DateTime capturedAt;
  final String deviceId;

  double? distanceFrom(AttendancePolicy policy) {
    if (policy.latitude == null || policy.longitude == null) return null;
    return Geolocator.distanceBetween(
      policy.latitude!,
      policy.longitude!,
      latitude,
      longitude,
    );
  }

  Map<String, dynamic> toPayload({
    required int outletId,
    required String requestId,
    String? outsideReason,
  }) {
    return {
      'outlet_id': outletId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'is_mock': isMock,
      'device_captured_at': capturedAt.toUtc().toIso8601String(),
      'device_id': deviceId,
      'request_id': requestId,
      'outside_reason': outsideReason,
      'source': 'mobile',
    };
  }
}

class AttendanceCaptureException implements Exception {
  const AttendanceCaptureException(
    this.message, {
    this.canOpenSettings = false,
  });

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

class AttendanceCaptureService {
  Future<AttendanceCaptureData> captureLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AttendanceCaptureException(
        'Layanan lokasi belum aktif. Aktifkan lokasi perangkat lalu coba lagi.',
        canOpenSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AttendanceCaptureException(
        'Izin lokasi diperlukan saat melakukan absensi.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AttendanceCaptureException(
        'Izin lokasi diblokir. Buka pengaturan aplikasi untuk mengaktifkannya.',
        canOpenSettings: true,
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_attendanceDeviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_attendanceDeviceIdKey, deviceId);
    }

    return AttendanceCaptureData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      isMock: position.isMocked,
      capturedAt: position.timestamp,
      deviceId: deviceId,
    );
  }

  Future<void> openSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
