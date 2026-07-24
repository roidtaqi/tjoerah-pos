import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/attendance_models.dart';
import '../providers/attendance_provider.dart';
import '../services/attendance_capture_service.dart';
import 'attendance_camera_screen.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(attendanceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absensi'),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan absensi',
            onPressed: _isSubmitting
                ? null
                : () => ref.read(attendanceProvider.notifier).refresh(),
            icon: const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isSubmitting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: attendance.when(
        loading: () => const AppLoadingState(message: 'Memuat absensi...'),
        error: (_, _) => AppErrorState(
          title: 'Absensi belum terhubung',
          message:
              'Pastikan server aktif dan akun terhubung dengan outlet serta profil karyawan.',
          onRetry: () => ref.read(attendanceProvider.notifier).refresh(),
        ),
        data: _buildAttendance,
      ),
    );
  }

  Widget _buildAttendance(AttendanceContextModel data) {
    final theme = Theme.of(context);
    final isCheckedIn = data.activeAttendance != null;
    final scheduleBlocksCheckIn =
        !isCheckedIn &&
        data.schedule != null &&
        data.schedule!.status != 'scheduled';
    final actionBlocked = data.pendingOfflineCount > 0 || scheduleBlocksCheckIn;
    final date = AppDateFormatter.weekdayLongDate(_now);
    final time = DateFormat('HH:mm:ss').format(_now);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(attendanceProvider.notifier).refresh(),
        child: ListView(
          padding: AppSpacing.page(context),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      time,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _EmployeeHeader(data: data),
                    if (data.pendingOfflineCount > 0) ...[
                      const SizedBox(height: 12),
                      _PendingSyncNotice(
                        count: data.pendingOfflineCount,
                        onSync: () =>
                            ref.read(attendanceProvider.notifier).refresh(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _SchedulePanel(data: data),
                    const SizedBox(height: 16),
                    AppButton(
                      text: isCheckedIn ? 'Absen pulang' : 'Absen masuk',
                      icon: isCheckedIn
                          ? Icons.logout_rounded
                          : Icons.login_rounded,
                      isLoading: _isSubmitting,
                      onPressed: actionBlocked
                          ? null
                          : () => _captureAttendance(
                              isCheckedIn ? 'check_out' : 'check_in',
                              data,
                            ),
                    ),
                    if (actionBlocked) ...[
                      const SizedBox(height: 8),
                      Text(
                        scheduleBlocksCheckIn
                            ? 'Anda tidak dijadwalkan masuk hari ini '
                                  '(${_scheduleStatusLabel(data.schedule!.status)}).'
                            : 'Selesaikan sinkronisasi absensi sebelumnya '
                                  'sebelum membuat catatan baru.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Riwayat terbaru',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          '${data.recentAttendance.length} catatan',
                          style: theme.textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (data.recentAttendance.isEmpty)
                      const AppCard(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Column(
                            children: [
                              Icon(Icons.event_available_outlined, size: 32),
                              SizedBox(height: 8),
                              Text('Belum ada riwayat absensi'),
                            ],
                          ),
                        ),
                      )
                    else
                      ...data.recentAttendance.map(
                        (record) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _AttendanceRow(record: record),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureAttendance(
    String action,
    AttendanceContextModel data,
  ) async {
    setState(() => _isSubmitting = true);
    AttendanceCaptureData capture;
    try {
      capture = await ref
          .read(attendanceCaptureServiceProvider)
          .captureLocation();
    } on AttendanceCaptureException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await _showLocationError(error);
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      _showMessage('Lokasi belum dapat diperoleh. Coba lagi di area terbuka.');
      return;
    }
    if (!mounted) return;

    final distance = capture.distanceFrom(data.policy);
    String? outsideReason;
    if (distance != null && distance > data.policy.geofenceRadiusMeters) {
      if (!data.policy.allowOutsideWithReason) {
        setState(() => _isSubmitting = false);
        _showMessage(
          'Anda berada ${distance.round()} meter dari outlet dan di luar area absensi.',
        );
        return;
      }
      outsideReason = await _askOutsideReason(distance);
      if (outsideReason == null || !mounted) {
        setState(() => _isSubmitting = false);
        return;
      }
    }

    setState(() => _isSubmitting = false);
    final photoPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AttendanceCameraScreen(
          actionLabel: action == 'check_in'
              ? 'Foto absen masuk'
              : 'Foto absen pulang',
        ),
      ),
    );
    if (photoPath == null || !mounted) return;

    setState(() => _isSubmitting = true);
    final result = await ref
        .read(attendanceProvider.notifier)
        .submit(
          action: action,
          photoPath: photoPath,
          capture: capture,
          outsideReason: outsideReason,
        );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    await _showResult(result);
  }

  Future<String?> _askOutsideReason(double distance) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Di luar area outlet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Jarak terdeteksi ${distance.round()} meter dari outlet.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan',
                hintText: 'Contoh: bertugas di booth acara',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.length >= 5) Navigator.pop(context, reason);
            },
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showLocationError(AttendanceCaptureException error) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lokasi diperlukan'),
        content: Text(error.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          if (error.canOpenSettings)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(attendanceCaptureServiceProvider).openSettings();
              },
              child: const Text('Buka pengaturan'),
            ),
        ],
      ),
    );
  }

  Future<void> _showResult(AttendanceSubmissionResult result) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final attendance = result.attendance;
        final isLate = attendance?.punctualityStatus == 'late';
        final color = result.isSuccess
            ? (result.isQueued || attendance?.reviewStatus == 'pending'
                  ? AppColors.warning
                  : isLate
                  ? AppColors.error
                  : AppColors.success)
            : AppColors.error;
        return AlertDialog(
          icon: Icon(
            result.isQueued
                ? Icons.cloud_upload_outlined
                : result.isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: color,
            size: 42,
          ),
          title: Text(
            result.isQueued
                ? 'Menunggu sinkronisasi'
                : result.isSuccess
                ? 'Absensi tercatat'
                : 'Absensi gagal',
          ),
          content: Text(result.message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Selesai'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}

class _EmployeeHeader extends StatelessWidget {
  const _EmployeeHeader({required this.data});

  final AttendanceContextModel data;

  @override
  Widget build(BuildContext context) {
    final checkedIn = data.activeAttendance != null;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            child: Text(
              data.employee.name.isEmpty
                  ? '?'
                  : data.employee.name.substring(0, 1).toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.employee.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  '${data.outlet.name} - ${data.employee.position ?? 'Karyawan'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AppBadge(
            text: checkedIn ? 'Sedang bekerja' : 'Belum masuk',
            color: checkedIn ? AppColors.successSoft : AppColors.surfaceMuted,
            textColor: checkedIn ? AppColors.success : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({required this.data});

  final AttendanceContextModel data;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm');
    final attendance = data.activeAttendance;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 21),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.schedule?.shiftName ?? 'Jadwal reguler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (data.schedule != null && data.schedule!.status != 'scheduled')
                AppBadge(
                  text: _scheduleStatusLabel(data.schedule!.status),
                  color: AppColors.surfaceMuted,
                  textColor: AppColors.textSecondary,
                )
              else
                Text(
                  '${time.format(data.scheduledStartAt.toLocal())} - '
                  '${time.format(data.scheduledEndAt.toLocal())}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
            ],
          ),
          if (attendance?.checkInAt != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _TimeValue(
                    label: 'Masuk',
                    value: time.format(attendance!.checkInAt!.toLocal()),
                  ),
                ),
                Expanded(
                  child: _TimeValue(
                    label: 'Pulang',
                    value: attendance.checkOutAt == null
                        ? '--:--'
                        : time.format(attendance.checkOutAt!.toLocal()),
                  ),
                ),
                AppBadge(
                  text: attendance.punctualityStatus == 'late'
                      ? 'Terlambat ${attendance.lateMinutes} mnt'
                      : 'Tepat waktu',
                  color: attendance.punctualityStatus == 'late'
                      ? AppColors.errorSoft
                      : AppColors.successSoft,
                  textColor: attendance.punctualityStatus == 'late'
                      ? AppColors.error
                      : AppColors.success,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _scheduleStatusLabel(String status) {
  return switch (status) {
    'leave' => 'Cuti',
    'sick' => 'Sakit',
    'off' => 'Libur',
    'cancelled' => 'Dibatalkan',
    _ => 'Dijadwalkan',
  };
}

class _TimeValue extends StatelessWidget {
  const _TimeValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _PendingSyncNotice extends StatelessWidget {
  const _PendingSyncNotice({required this.count, required this.onSync});

  final int count;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_outlined, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text('$count absensi menunggu sinkronisasi')),
          IconButton(
            tooltip: 'Sinkronkan sekarang',
            onPressed: onSync,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm');
    final isLate = record.punctualityStatus == 'late';
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isLate ? AppColors.errorSoft : AppColors.successSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isLate ? Icons.schedule_outlined : Icons.done_rounded,
              color: isLate ? AppColors.error : AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.workDate == null
                      ? 'Absensi'
                      : AppDateFormatter.longDate(record.workDate!.toLocal()),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.checkInAt == null ? '--:--' : time.format(record.checkInAt!.toLocal())} - '
                  '${record.checkOutAt == null ? '--:--' : time.format(record.checkOutAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AppBadge(
            text: record.reviewStatus == 'pending'
                ? 'Ditinjau'
                : isLate
                ? 'Terlambat'
                : 'Tepat waktu',
            color: record.reviewStatus == 'pending'
                ? AppColors.warningSoft
                : isLate
                ? AppColors.errorSoft
                : AppColors.successSoft,
            textColor: record.reviewStatus == 'pending'
                ? AppColors.warning
                : isLate
                ? AppColors.error
                : AppColors.success,
          ),
        ],
      ),
    );
  }
}
