import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
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
                            'Jadwal mendatang',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isSubmitting
                              ? null
                              : () => _openChangeRequest(data),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Ajukan perubahan'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _UpcomingSchedulePanel(schedules: data.upcomingSchedules),
                    if (data.changeRequests.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Status pengajuan',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _ChangeRequestPanel(requests: data.changeRequests),
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

  Future<void> _openChangeRequest(AttendanceContextModel data) async {
    final payload = await AppBottomSheet.show<Map<String, dynamic>>(
      context,
      title: 'Ajukan perubahan jadwal',
      subtitle: 'Permintaan akan ditinjau oleh admin atau owner',
      child: _ShiftChangeRequestForm(
        schedules: data.upcomingSchedules,
        shifts: data.availableShifts,
      ),
    );
    if (payload == null || !mounted) return;
    setState(() => _isSubmitting = true);
    final result = await ref
        .read(attendanceProvider.notifier)
        .requestScheduleChange(payload);
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
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
                  data.schedule?.shiftName ??
                      data.attendanceShift?.name ??
                      'Jam kerja cadangan',
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
          if ((data.schedule == null || data.schedule!.status == 'scheduled') &&
              data.scheduledLateAfterAt != null) ...[
            const SizedBox(height: 7),
            Text(
              'Mulai dihitung terlambat pukul '
              '${time.format(data.scheduledLateAfterAt!.toLocal())}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
            ),
          ],
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

class _UpcomingSchedulePanel extends StatelessWidget {
  const _UpcomingSchedulePanel({required this.schedules});

  final List<EmployeeScheduleModel> schedules;

  @override
  Widget build(BuildContext context) {
    if (schedules.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.event_busy_outlined),
            SizedBox(width: 10),
            Expanded(child: Text('Belum ada roster yang diterbitkan.')),
          ],
        ),
      );
    }
    final time = DateFormat('HH:mm');
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < schedules.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              leading: SizedBox(
                width: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      schedules[index].workDate.toLocal().day.toString(),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      AppDateFormatter.dayMonth(
                        schedules[index].workDate.toLocal(),
                      ).split(' ').last,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              title: Text(_scheduleTitle(schedules[index])),
              subtitle: Text(
                schedules[index].status == 'scheduled'
                    ? '${time.format(schedules[index].startAt.toLocal())} - '
                          '${time.format(schedules[index].endAt.toLocal())}'
                    : AppDateFormatter.weekdayLongDate(
                        schedules[index].workDate.toLocal(),
                      ),
              ),
              trailing: schedules[index].isCustomTime
                  ? const AppBadge(
                      text: 'Khusus',
                      icon: Icons.tune_rounded,
                      color: AppColors.infoSoft,
                      textColor: AppColors.info,
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeRequestPanel extends StatelessWidget {
  const _ChangeRequestPanel({required this.requests});

  final List<ShiftChangeRequestModel> requests;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < requests.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              leading: Icon(_requestStatusIcon(requests[index].status)),
              title: Text(
                '${AppDateFormatter.shortDate(requests[index].requestedWorkDate.toLocal())} - '
                '${_requestAssignment(requests[index])}',
              ),
              subtitle: Text(
                requests[index].responseNotes ?? requests[index].reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: AppBadge(
                text: _requestStatusLabel(requests[index].status),
                color: _requestStatusSoftColor(requests[index].status),
                textColor: _requestStatusColor(requests[index].status),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShiftChangeRequestForm extends StatefulWidget {
  const _ShiftChangeRequestForm({
    required this.schedules,
    required this.shifts,
  });

  final List<EmployeeScheduleModel> schedules;
  final List<AttendanceShiftModel> shifts;

  @override
  State<_ShiftChangeRequestForm> createState() =>
      _ShiftChangeRequestFormState();
}

class _ShiftChangeRequestFormState extends State<_ShiftChangeRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late DateTime _date;
  late String _assignment;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _lateAfter = const TimeOfDay(hour: 8, minute: 15);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);

  @override
  void initState() {
    super.initState();
    _date = widget.schedules.isEmpty
        ? DateTime.now()
        : widget.schedules.first.workDate.toLocal();
    _assignment = widget.shifts.isEmpty
        ? 'custom'
        : 'shift:${widget.shifts.first.id}';
    _applyScheduleForDate();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tanggal yang ingin diubah',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(AppDateFormatter.weekdayLongDate(_date)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _assignment,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Jadwal yang diminta',
                prefixIcon: Icon(Icons.swap_horiz_rounded),
              ),
              items: [
                ...widget.shifts.map(
                  (shift) => DropdownMenuItem(
                    value: 'shift:${shift.id}',
                    child: Text(
                      '${shift.name} (${shift.startTime}-${shift.endTime})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const DropdownMenuItem(
                  value: 'custom',
                  child: Text('Jam kerja khusus'),
                ),
                const DropdownMenuItem(value: 'off', child: Text('Off')),
                const DropdownMenuItem(value: 'leave', child: Text('Cuti')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _assignment = value);
              },
            ),
            if (_assignment == 'custom') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RequestTimeField(
                      label: 'Mulai',
                      value: _start,
                      onTap: () => _pickTime('start'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RequestTimeField(
                      label: 'Terlambat',
                      value: _lateAfter,
                      onTap: () => _pickTime('late'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _RequestTimeField(
                      label: 'Selesai',
                      value: _end,
                      onTap: () => _pickTime('end'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alasan pengajuan',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              validator: (value) => (value ?? '').trim().length < 5
                  ? 'Alasan minimal 5 karakter'
                  : null,
            ),
            const SizedBox(height: 18),
            AppButton(
              text: 'Kirim permintaan',
              icon: Icons.send_outlined,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDate: _date.isBefore(DateTime.now()) ? DateTime.now() : _date,
    );
    if (selected == null) return;
    setState(() {
      _date = selected;
      _applyScheduleForDate();
    });
  }

  void _applyScheduleForDate() {
    EmployeeScheduleModel? schedule;
    for (final candidate in widget.schedules) {
      if (_sameDay(candidate.workDate.toLocal(), _date)) {
        schedule = candidate;
        break;
      }
    }
    if (schedule == null) return;
    if (schedule.status != 'scheduled') {
      _assignment = schedule.status == 'leave' ? 'leave' : 'off';
    } else if (schedule.attendanceShiftId != null &&
        widget.shifts.any((shift) => shift.id == schedule!.attendanceShiftId)) {
      _assignment = 'shift:${schedule.attendanceShiftId}';
    } else {
      _assignment = 'custom';
      _start = TimeOfDay.fromDateTime(schedule.startAt.toLocal());
      _lateAfter = TimeOfDay.fromDateTime(
        schedule.lateAfterAt?.toLocal() ?? schedule.startAt.toLocal(),
      );
      _end = TimeOfDay.fromDateTime(schedule.endAt.toLocal());
    }
  }

  Future<void> _pickTime(String type) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: type == 'start'
          ? _start
          : type == 'late'
          ? _lateAfter
          : _end,
    );
    if (selected == null) return;
    setState(() {
      if (type == 'start') _start = selected;
      if (type == 'late') _lateAfter = selected;
      if (type == 'end') _end = selected;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_assignment == 'custom' &&
        !_requestTimeIsValid(_start, _lateAfter, _end)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Batas terlambat harus berada dalam jam kerja.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final payload = <String, dynamic>{
      'requested_work_date': _requestDateKey(_date),
      'requested_status':
          _assignment.startsWith('shift:') || _assignment == 'custom'
          ? 'scheduled'
          : _assignment,
      'reason': _reason.text.trim(),
    };
    if (_assignment.startsWith('shift:')) {
      payload['requested_attendance_shift_id'] = int.parse(
        _assignment.split(':').last,
      );
    } else if (_assignment == 'custom') {
      payload.addAll({
        'requested_start_time': _requestTime(_start),
        'requested_late_after_time': _requestTime(_lateAfter),
        'requested_end_time': _requestTime(_end),
      });
    }
    Navigator.pop(context, payload);
  }
}

class _RequestTimeField extends StatelessWidget {
  const _RequestTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value.format(context)),
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

String _scheduleTitle(EmployeeScheduleModel schedule) {
  return schedule.status == 'scheduled'
      ? schedule.shiftName
      : _scheduleStatusLabel(schedule.status);
}

String _requestAssignment(ShiftChangeRequestModel request) {
  if (request.requestedStatus != 'scheduled') {
    return _scheduleStatusLabel(request.requestedStatus);
  }
  if (request.requestedAttendanceShift != null) {
    return request.requestedAttendanceShift!.name;
  }
  final start = request.requestedStartTime;
  final end = request.requestedEndTime;
  return start == null || end == null
      ? 'Jam khusus'
      : 'Jam khusus ${start.substring(0, 5)}-${end.substring(0, 5)}';
}

String _requestStatusLabel(String status) {
  return switch (status) {
    'approved' => 'Disetujui',
    'rejected' => 'Ditolak',
    'cancelled' => 'Dibatalkan',
    _ => 'Menunggu',
  };
}

IconData _requestStatusIcon(String status) {
  return switch (status) {
    'approved' => Icons.check_circle_outline_rounded,
    'rejected' => Icons.cancel_outlined,
    'cancelled' => Icons.block_outlined,
    _ => Icons.hourglass_top_rounded,
  };
}

Color _requestStatusColor(String status) {
  return switch (status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.error,
    'cancelled' => AppColors.textSecondary,
    _ => AppColors.warning,
  };
}

Color _requestStatusSoftColor(String status) {
  return switch (status) {
    'approved' => AppColors.successSoft,
    'rejected' => AppColors.errorSoft,
    'cancelled' => AppColors.surfaceMuted,
    _ => AppColors.warningSoft,
  };
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _requestDateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _requestTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

bool _requestTimeIsValid(TimeOfDay start, TimeOfDay lateAfter, TimeOfDay end) {
  final startMinutes = (start.hour * 60) + start.minute;
  var lateMinutes = (lateAfter.hour * 60) + lateAfter.minute;
  var endMinutes = (end.hour * 60) + end.minute;
  if (endMinutes <= startMinutes) endMinutes += 1440;
  if (lateMinutes < startMinutes) lateMinutes += 1440;
  return lateMinutes <= endMinutes;
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
