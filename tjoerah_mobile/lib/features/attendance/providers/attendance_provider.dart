import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/attendance_models.dart';
import '../repositories/attendance_repository.dart';
import '../services/attendance_capture_service.dart';
import '../services/attendance_photo_optimizer.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => AttendanceRepository(),
);

final attendanceCaptureServiceProvider = Provider<AttendanceCaptureService>(
  (ref) => AttendanceCaptureService(),
);

final attendancePhotoOptimizerProvider = Provider<AttendancePhotoOptimizer>(
  (ref) => AttendancePhotoOptimizer(),
);

class AttendanceNotifier extends AsyncNotifier<AttendanceContextModel> {
  AttendanceRepository get _repository =>
      ref.read(attendanceRepositoryProvider);

  @override
  Future<AttendanceContextModel> build() async {
    await _repository.syncPending();
    return _repository.getContext();
  }

  Future<void> refresh() async {
    final previous = state.value;
    state = const AsyncValue.loading();
    try {
      await _repository.syncPending();
      state = AsyncValue.data(await _repository.getContext());
    } catch (error, stackTrace) {
      state = previous == null
          ? AsyncValue.error(error, stackTrace)
          : AsyncValue.data(previous);
    }
  }

  Future<AttendanceSubmissionResult> submit({
    required String action,
    required String photoPath,
    required AttendanceCaptureData capture,
    String? outsideReason,
  }) async {
    final context = state.value;
    if (context == null) {
      return const AttendanceSubmissionResult(
        isSuccess: false,
        message: 'Data absensi belum siap. Muat ulang lalu coba lagi.',
      );
    }
    final payload = capture.toPayload(
      outletId: context.outlet.id,
      requestId: const Uuid().v4(),
      outsideReason: outsideReason,
    );
    if (action == 'check_out' && context.activeAttendance != null) {
      payload['attendance_log_id'] = context.activeAttendance!.id;
    }

    OptimizedAttendancePhoto optimizedPhoto;
    try {
      optimizedPhoto = await ref
          .read(attendancePhotoOptimizerProvider)
          .optimize(photoPath);
    } on AttendancePhotoOptimizationException catch (error) {
      return AttendanceSubmissionResult(
        isSuccess: false,
        message: error.message,
      );
    } catch (_) {
      return const AttendanceSubmissionResult(
        isSuccess: false,
        message: 'Foto belum dapat diproses. Ambil foto kembali.',
      );
    }

    try {
      final result = await _repository.submit(
        action: action,
        payload: payload,
        photoPath: optimizedPhoto.path,
      );
      state = AsyncValue.data(await _repository.getContext());
      return result;
    } on AttendanceApiException catch (error) {
      return AttendanceSubmissionResult(
        isSuccess: false,
        message: error.message,
      );
    } catch (_) {
      try {
        await _repository.queue(
          action: action,
          payload: payload,
          photoPath: optimizedPhoto.path,
        );
        state = AsyncValue.data(
          context.copyWith(
            pendingOfflineCount: context.pendingOfflineCount + 1,
          ),
        );
        return const AttendanceSubmissionResult(
          isSuccess: true,
          isQueued: true,
          message:
              'Absensi disimpan sementara dan akan diverifikasi saat server terhubung.',
        );
      } catch (_) {
        return const AttendanceSubmissionResult(
          isSuccess: false,
          message:
              'Absensi belum dapat disimpan. Periksa ruang penyimpanan dan koneksi.',
        );
      }
    } finally {
      await optimizedPhoto.delete();
    }
  }

  Future<AttendanceSubmissionResult> requestScheduleChange(
    Map<String, dynamic> data,
  ) async {
    try {
      await _repository.createShiftChangeRequest(data);
      state = AsyncValue.data(await _repository.getContext());
      return const AttendanceSubmissionResult(
        isSuccess: true,
        message: 'Permintaan perubahan jadwal berhasil dikirim.',
      );
    } on AttendanceApiException catch (error) {
      return AttendanceSubmissionResult(
        isSuccess: false,
        message: error.message,
      );
    } catch (_) {
      return const AttendanceSubmissionResult(
        isSuccess: false,
        message: 'Permintaan belum dapat dikirim. Periksa koneksi server.',
      );
    }
  }
}

final attendanceProvider =
    AsyncNotifierProvider<AttendanceNotifier, AttendanceContextModel>(
      AttendanceNotifier.new,
    );
