import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/app_date_formatter.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/attendance_models.dart';
import '../providers/attendance_admin_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/attendance_capture_service.dart';

class AttendanceAdminScreen extends ConsumerStatefulWidget {
  const AttendanceAdminScreen({super.key});

  @override
  ConsumerState<AttendanceAdminScreen> createState() =>
      _AttendanceAdminScreenState();
}

class _AttendanceAdminScreenState extends ConsumerState<AttendanceAdminScreen> {
  bool _isMutating = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (!canManageCatalogForUser(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manajemen absensi')),
        body: const AppErrorState(
          title: 'Akses dibatasi',
          message: 'Hanya owner atau admin yang dapat membuka laporan absensi.',
        ),
      );
    }

    final admin = ref.watch(attendanceAdminProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manajemen absensi'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang data',
              onPressed: _isMutating
                  ? null
                  : () => ref.read(attendanceAdminProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.analytics_outlined), text: 'Laporan'),
              Tab(icon: Icon(Icons.calendar_month_outlined), text: 'Jadwal'),
              Tab(icon: Icon(Icons.tune_rounded), text: 'Kebijakan'),
            ],
          ),
        ),
        body: admin.when(
          loading: () =>
              const AppLoadingState(message: 'Memuat data absensi...'),
          error: (_, _) => AppErrorState(
            title: 'Data absensi belum tersedia',
            message: 'Pastikan server aktif dan akun memiliki akses ke outlet.',
            onRetry: () => ref.read(attendanceAdminProvider.notifier).refresh(),
          ),
          data: (data) => Column(
            children: [
              _OutletSelector(
                data: data,
                enabled: !_isMutating,
                onSelected: (outlet) => ref
                    .read(attendanceAdminProvider.notifier)
                    .selectOutlet(outlet),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ReportTab(
                      data: data,
                      enabled: !_isMutating,
                      onDateRange: () => _selectDateRange(data),
                      onStatus: (status) => ref
                          .read(attendanceAdminProvider.notifier)
                          .setFilters(status: status),
                      onReview: _openReview,
                      onPhoto: _openPhoto,
                      onExport: () => _exportReport(data),
                    ),
                    _ScheduleTab(
                      data: data,
                      enabled: !_isMutating,
                      onAdd: () => _openScheduleForm(data),
                      onEdit: (schedule) => _openScheduleForm(data, schedule),
                      onDelete: _confirmDeleteSchedule,
                    ),
                    _PolicyTab(
                      key: ValueKey(data.selectedOutlet.id),
                      policy: data.policy,
                      enabled: !_isMutating,
                      onSave: _savePolicy,
                      captureService: ref.read(
                        attendanceCaptureServiceProvider,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateRange(AttendanceAdminState data) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: DateTimeRange(start: data.dateFrom, end: data.dateTo),
    );
    if (range == null) return;
    await ref
        .read(attendanceAdminProvider.notifier)
        .setFilters(dateFrom: range.start, dateTo: range.end);
  }

  Future<void> _savePolicy(AttendancePolicy policy) async {
    setState(() => _isMutating = true);
    final result = await ref
        .read(attendanceAdminProvider.notifier)
        .savePolicy(policy);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _openScheduleForm(
    AttendanceAdminState data, [
    EmployeeScheduleModel? schedule,
  ]) async {
    final payload = await AppBottomSheet.show<Map<String, dynamic>>(
      context,
      title: schedule == null ? 'Jadwal baru' : 'Edit jadwal',
      subtitle: 'Tetapkan waktu kerja karyawan untuk tanggal tertentu',
      child: _ScheduleForm(
        employees: data.employees,
        outletId: data.selectedOutlet.id,
        schedule: schedule,
      ),
    );
    if (payload == null || !mounted) return;
    setState(() => _isMutating = true);
    final result = await ref
        .read(attendanceAdminProvider.notifier)
        .saveSchedule(payload, scheduleId: schedule?.id);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _confirmDeleteSchedule(EmployeeScheduleModel schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus jadwal?'),
        content: Text(
          'Jadwal ${schedule.employee?.name ?? 'karyawan'} pada '
          '${AppDateFormatter.longDate(schedule.workDate)} akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isMutating = true);
    final result = await ref
        .read(attendanceAdminProvider.notifier)
        .deleteSchedule(schedule);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _openReview(AttendanceRecord attendance) async {
    final payload = await AppBottomSheet.show<Map<String, dynamic>>(
      context,
      title: 'Periksa absensi',
      subtitle: attendance.employee?.name ?? 'Karyawan',
      child: _ReviewForm(attendance: attendance),
    );
    if (payload == null || !mounted) return;
    setState(() => _isMutating = true);
    final result = await ref
        .read(attendanceAdminProvider.notifier)
        .review(attendance, payload);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _openPhoto(AttendanceRecord record, String type) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        type == 'check-in'
                            ? 'Foto absen masuk'
                            : 'Foto absen pulang',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: FutureBuilder<Uint8List>(
                  future: ref
                      .read(attendanceRepositoryProvider)
                      .getPhoto(record.id, type),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        height: 320,
                        child: AppLoadingState(message: 'Memuat foto...'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const SizedBox(
                        height: 260,
                        child: AppErrorState(
                          message: 'Foto belum dapat dimuat.',
                        ),
                      );
                    }
                    return Image.memory(snapshot.data!, fit: BoxFit.contain);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportReport(AttendanceAdminState data) async {
    setState(() => _isMutating = true);
    try {
      final bytes = await ref
          .read(attendanceRepositoryProvider)
          .exportReport(
            outletId: data.selectedOutlet.id,
            dateFrom: data.dateFrom,
            dateTo: data.dateTo,
            status: data.status,
          );
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/laporan-absensi-'
        '${DateFormat('yyyyMMdd').format(data.dateFrom)}-'
        '${DateFormat('yyyyMMdd').format(data.dateTo)}.csv',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Laporan absensi ${data.selectedOutlet.name}',
        ),
      );
    } catch (_) {
      if (mounted) {
        _showResult(
          const AttendanceAdminResult(false, 'Laporan belum dapat diekspor.'),
        );
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  void _showResult(AttendanceAdminResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
  }
}

class _OutletSelector extends StatelessWidget {
  const _OutletSelector({
    required this.data,
    required this.enabled,
    required this.onSelected,
  });

  final AttendanceAdminState data;
  final bool enabled;
  final ValueChanged<AttendanceOutlet> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.store_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.selectedOutlet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          PopupMenuButton<int>(
            tooltip: 'Pilih outlet',
            enabled: enabled && data.outlets.length > 1,
            onSelected: (id) => onSelected(
              data.outlets.firstWhere((outlet) => outlet.id == id),
            ),
            itemBuilder: (context) => data.outlets
                .map(
                  (outlet) =>
                      PopupMenuItem(value: outlet.id, child: Text(outlet.name)),
                )
                .toList(),
            icon: const Icon(Icons.expand_more_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReportTab extends StatelessWidget {
  const _ReportTab({
    required this.data,
    required this.enabled,
    required this.onDateRange,
    required this.onStatus,
    required this.onReview,
    required this.onPhoto,
    required this.onExport,
  });

  final AttendanceAdminState data;
  final bool enabled;
  final VoidCallback onDateRange;
  final ValueChanged<String> onStatus;
  final ValueChanged<AttendanceRecord> onReview;
  final void Function(AttendanceRecord, String) onPhoto;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.page(context),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: enabled ? onDateRange : null,
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        '${AppDateFormatter.longDate(data.dateFrom)} - '
                        '${AppDateFormatter.longDate(data.dateTo)}',
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: data.status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua')),
                          DropdownMenuItem(
                            value: 'on_time',
                            child: Text('Tepat waktu'),
                          ),
                          DropdownMenuItem(
                            value: 'late',
                            child: Text('Terlambat'),
                          ),
                          DropdownMenuItem(
                            value: 'pending_review',
                            child: Text('Perlu ditinjau'),
                          ),
                          DropdownMenuItem(
                            value: 'early_leave',
                            child: Text('Pulang cepat'),
                          ),
                        ],
                        onChanged: enabled
                            ? (value) {
                                if (value != null) onStatus(value);
                              }
                            : null,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Ekspor CSV',
                      onPressed: enabled ? onExport : null,
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 760 ? 4 : 2;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 10) / columns;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SummaryTile(
                          width: width,
                          label: 'Hadir',
                          value: '${data.summary.total}',
                          icon: Icons.how_to_reg_outlined,
                          color: AppColors.info,
                        ),
                        _SummaryTile(
                          width: width,
                          label: 'Tepat waktu',
                          value: '${data.summary.onTime}',
                          icon: Icons.check_circle_outline_rounded,
                          color: AppColors.success,
                        ),
                        _SummaryTile(
                          width: width,
                          label: 'Terlambat',
                          value: '${data.summary.late}',
                          icon: Icons.schedule_outlined,
                          color: AppColors.error,
                        ),
                        _SummaryTile(
                          width: width,
                          label: 'Perlu ditinjau',
                          value: '${data.summary.pendingReview}',
                          icon: Icons.fact_check_outlined,
                          color: AppColors.warning,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Catatan absensi',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${data.records.length} data',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (data.records.isEmpty)
                  const AppEmptyState(
                    title: 'Belum ada data',
                    message: 'Tidak ada absensi untuk periode dan filter ini.',
                    icon: Icons.event_busy_outlined,
                  )
                else
                  ...data.records.map(
                    (record) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _AdminAttendanceRow(
                        record: record,
                        enabled: enabled,
                        onReview: () => onReview(record),
                        onPhoto: (type) => onPhoto(record, type),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 92,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 25),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAttendanceRow extends StatelessWidget {
  const _AdminAttendanceRow({
    required this.record,
    required this.enabled,
    required this.onReview,
    required this.onPhoto,
  });

  final AttendanceRecord record;
  final bool enabled;
  final VoidCallback onReview;
  final ValueChanged<String> onPhoto;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm');
    final isLate = record.punctualityStatus == 'late';
    return AppCard(
      onTap: enabled ? onReview : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: record.reviewStatus == 'pending'
                  ? AppColors.warningSoft
                  : isLate
                  ? AppColors.errorSoft
                  : AppColors.successSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              record.reviewStatus == 'pending'
                  ? Icons.fact_check_outlined
                  : isLate
                  ? Icons.schedule_outlined
                  : Icons.done_rounded,
              color: record.reviewStatus == 'pending'
                  ? AppColors.warning
                  : isLate
                  ? AppColors.error
                  : AppColors.success,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.employee?.name ?? 'Karyawan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.workDate == null ? '-' : AppDateFormatter.dayMonth(record.workDate!.toLocal())} - '
                  '${record.checkInAt == null ? '--:--' : time.format(record.checkInAt!.toLocal())} / '
                  '${record.checkOutAt == null ? '--:--' : time.format(record.checkOutAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppBadge(
                      text: isLate
                          ? 'Terlambat ${record.lateMinutes} mnt'
                          : 'Tepat waktu',
                      color: isLate
                          ? AppColors.errorSoft
                          : AppColors.successSoft,
                      textColor: isLate ? AppColors.error : AppColors.success,
                    ),
                    if (record.reviewStatus == 'pending')
                      const AppBadge(
                        text: 'Perlu ditinjau',
                        color: AppColors.warningSoft,
                        textColor: AppColors.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (record.hasCheckInPhoto)
            IconButton(
              tooltip: 'Foto masuk',
              onPressed: enabled ? () => onPhoto('check-in') : null,
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          PopupMenuButton<String>(
            tooltip: 'Aksi absensi',
            enabled: enabled,
            onSelected: (value) {
              if (value == 'review') onReview();
              if (value == 'check-out-photo') onPhoto('check-out');
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'review',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('Periksa'),
                ),
              ),
              if (record.hasCheckOutPhoto)
                const PopupMenuItem(
                  value: 'check-out-photo',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.photo_camera_back_outlined),
                    title: Text('Foto pulang'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({
    required this.data,
    required this.enabled,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final AttendanceAdminState data;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<EmployeeScheduleModel> onEdit;
  final ValueChanged<EmployeeScheduleModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm');
    return ListView(
      padding: AppSpacing.page(context),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Jadwal karyawan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: enabled ? onAdd : null,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (data.employees.isEmpty)
                  const AppEmptyState(
                    title: 'Belum ada karyawan',
                    message:
                        'Hubungkan akun pengguna dengan profil karyawan terlebih dahulu.',
                    icon: Icons.badge_outlined,
                  )
                else if (data.schedules.isEmpty)
                  AppEmptyState(
                    title: 'Belum ada jadwal khusus',
                    message:
                        'Tanpa jadwal khusus, kebijakan jam kerja outlet tetap digunakan.',
                    icon: Icons.calendar_month_outlined,
                    onAction: enabled ? onAdd : null,
                    actionLabel: enabled ? 'Tambah jadwal' : null,
                  )
                else
                  ...data.schedules.map(
                    (schedule) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: enabled ? () => onEdit(schedule) : null,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.calendar_today_outlined),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    schedule.employee?.name ?? 'Karyawan',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${AppDateFormatter.weekdayShortDate(schedule.workDate.toLocal())} - '
                                    '${time.format(schedule.startAt.toLocal())}-${time.format(schedule.endAt.toLocal())}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 7),
                                  AppBadge(
                                    text: schedule.shiftName,
                                    icon: Icons.schedule_rounded,
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Aksi jadwal',
                              enabled: enabled,
                              onSelected: (value) {
                                if (value == 'edit') onEdit(schedule);
                                if (value == 'delete') onDelete(schedule);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Edit'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(Icons.delete_outline_rounded),
                                    title: Text('Hapus'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PolicyTab extends StatefulWidget {
  const _PolicyTab({
    super.key,
    required this.policy,
    required this.enabled,
    required this.onSave,
    required this.captureService,
  });

  final AttendancePolicy policy;
  final bool enabled;
  final ValueChanged<AttendancePolicy> onSave;
  final AttendanceCaptureService captureService;

  @override
  State<_PolicyTab> createState() => _PolicyTabState();
}

class _PolicyTabState extends State<_PolicyTab> {
  final _formKey = GlobalKey<FormState>();
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _tolerance;
  late final TextEditingController _openMinutes;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _radius;
  late final TextEditingController _accuracy;
  late final TextEditingController _retention;
  late bool _requireCheckInPhoto;
  late bool _requireCheckOutPhoto;
  late bool _allowOutside;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _start = _parseTime(policy.workStartTime);
    _end = _parseTime(policy.workEndTime);
    _tolerance = TextEditingController(
      text: policy.lateToleranceMinutes.toString(),
    );
    _openMinutes = TextEditingController(
      text: policy.checkInOpenMinutes.toString(),
    );
    _latitude = TextEditingController(text: policy.latitude?.toString() ?? '');
    _longitude = TextEditingController(
      text: policy.longitude?.toString() ?? '',
    );
    _radius = TextEditingController(
      text: policy.geofenceRadiusMeters.toString(),
    );
    _accuracy = TextEditingController(
      text: policy.maximumAccuracyMeters.toString(),
    );
    _retention = TextEditingController(
      text: policy.photoRetentionDays.toString(),
    );
    _requireCheckInPhoto = policy.requireCheckInPhoto;
    _requireCheckOutPhoto = policy.requireCheckOutPhoto;
    _allowOutside = policy.allowOutsideWithReason;
  }

  @override
  void dispose() {
    _tolerance.dispose();
    _openMinutes.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _radius.dispose();
    _accuracy.dispose();
    _retention.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.page(context),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Jam kerja',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _TimeField(
                          label: 'Mulai',
                          value: _start,
                          onTap: widget.enabled ? () => _pickTime(true) : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeField(
                          label: 'Selesai',
                          value: _end,
                          onTap: widget.enabled ? () => _pickTime(false) : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          controller: _tolerance,
                          label: 'Toleransi terlambat',
                          suffix: 'menit',
                          max: 240,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          controller: _openMinutes,
                          label: 'Absen dibuka',
                          suffix: 'menit sebelum',
                          max: 720,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Area outlet',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.enabled ? _useCurrentLocation : null,
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Ambil lokasi'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                          validator: _optionalDecimal,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                          validator: _optionalDecimal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          controller: _radius,
                          label: 'Radius geofence',
                          suffix: 'meter',
                          min: 20,
                          max: 5000,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          controller: _accuracy,
                          label: 'Akurasi maksimum',
                          suffix: 'meter',
                          min: 10,
                          max: 2000,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Bukti & pemeriksaan',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Foto saat masuk'),
                    value: _requireCheckInPhoto,
                    onChanged: widget.enabled
                        ? (value) =>
                              setState(() => _requireCheckInPhoto = value)
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Foto saat pulang'),
                    value: _requireCheckOutPhoto,
                    onChanged: widget.enabled
                        ? (value) =>
                              setState(() => _requireCheckOutPhoto = value)
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Izinkan di luar area dengan alasan'),
                    value: _allowOutside,
                    onChanged: widget.enabled
                        ? (value) => setState(() => _allowOutside = value)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  _NumberField(
                    controller: _retention,
                    label: 'Retensi foto',
                    suffix: 'hari',
                    min: 30,
                    max: 3650,
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    text: 'Simpan kebijakan',
                    icon: Icons.save_outlined,
                    onPressed: widget.enabled ? _submit : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickTime(bool isStart) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    try {
      final capture = await widget.captureService.captureLocation();
      if (!mounted) return;
      setState(() {
        _latitude.text = capture.latitude.toStringAsFixed(7);
        _longitude.text = capture.longitude.toStringAsFixed(7);
      });
    } on AttendanceCaptureException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(
      AttendancePolicy(
        outletId: widget.policy.outletId,
        timezone: widget.policy.timezone,
        workStartTime: _formatTime(_start),
        workEndTime: _formatTime(_end),
        lateToleranceMinutes: int.parse(_tolerance.text),
        checkInOpenMinutes: int.parse(_openMinutes.text),
        latitude: double.tryParse(_latitude.text),
        longitude: double.tryParse(_longitude.text),
        geofenceRadiusMeters: int.parse(_radius.text),
        maximumAccuracyMeters: int.parse(_accuracy.text),
        requireCheckInPhoto: _requireCheckInPhoto,
        requireCheckOutPhoto: _requireCheckOutPhoto,
        allowOutsideWithReason: _allowOutside,
        photoRetentionDays: int.parse(_retention.text),
      ),
    );
  }

  String? _optionalDecimal(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty || double.tryParse(text) != null
        ? null
        : 'Angka tidak valid';
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final TimeOfDay value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.schedule_rounded),
        ),
        child: Text(value.format(context)),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.min = 0,
    this.max,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final int min;
  final int? max;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: (value) {
        final parsed = int.tryParse(value ?? '');
        if (parsed == null) return 'Angka tidak valid';
        if (parsed < min) return 'Minimal $min';
        if (max != null && parsed > max!) return 'Maksimal $max';
        return null;
      },
    );
  }
}

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm({
    required this.employees,
    required this.outletId,
    required this.schedule,
  });

  final List<AttendanceEmployee> employees;
  final int outletId;
  final EmployeeScheduleModel? schedule;

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  final _formKey = GlobalKey<FormState>();
  late int? _employeeId;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final TextEditingController _name;
  late final TextEditingController _notes;
  String _status = 'scheduled';

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    _employeeId =
        schedule?.employeeId ??
        (widget.employees.isEmpty ? null : widget.employees.first.id);
    _date = schedule?.workDate.toLocal() ?? DateTime.now();
    _start = schedule == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay.fromDateTime(schedule.startAt.toLocal());
    _end = schedule == null
        ? const TimeOfDay(hour: 17, minute: 0)
        : TimeOfDay.fromDateTime(schedule.endAt.toLocal());
    _name = TextEditingController(text: schedule?.shiftName ?? 'Reguler');
    _notes = TextEditingController(text: schedule?.notes);
    _status = schedule?.status ?? 'scheduled';
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
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
            DropdownButtonFormField<int>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Karyawan',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: widget.employees
                  .map(
                    (employee) => DropdownMenuItem(
                      value: employee.id,
                      child: Text(
                        employee.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _employeeId = value),
              validator: (value) => value == null ? 'Pilih karyawan' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Tanggal',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(AppDateFormatter.weekdayLongDate(_date)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Mulai',
                    value: _start,
                    onTap: () => _pickTime(true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: 'Selesai',
                    value: _end,
                    onTap: () => _pickTime(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nama shift',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Nama shift wajib diisi'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status jadwal',
                prefixIcon: Icon(Icons.event_available_outlined),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'scheduled',
                  child: Text('Dijadwalkan'),
                ),
                DropdownMenuItem(value: 'leave', child: Text('Cuti')),
                DropdownMenuItem(value: 'sick', child: Text('Sakit')),
                DropdownMenuItem(value: 'off', child: Text('Libur')),
                DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              text: widget.schedule == null
                  ? 'Tambah jadwal'
                  : 'Simpan perubahan',
              icon: Icons.check_rounded,
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
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _date,
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _pickTime(bool isStart) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _start.hour,
      _start.minute,
    );
    var end = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _end.hour,
      _end.minute,
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    Navigator.pop(context, {
      'employee_id': _employeeId,
      'outlet_id': widget.outletId,
      'work_date': DateFormat('yyyy-MM-dd').format(_date),
      'start_at': start.toUtc().toIso8601String(),
      'end_at': end.toUtc().toIso8601String(),
      'shift_name': _name.text.trim(),
      'status': _status,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    });
  }
}

class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.attendance});

  final AttendanceRecord attendance;

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  final _formKey = GlobalKey<FormState>();
  late String _status;
  late DateTime? _checkIn;
  late DateTime? _checkOut;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _status = widget.attendance.reviewStatus;
    _checkIn = widget.attendance.checkInAt?.toLocal();
    _checkOut = widget.attendance.checkOutAt?.toLocal();
    _notes = TextEditingController(text: widget.attendance.reviewNotes);
  }

  @override
  void dispose() {
    _notes.dispose();
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
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Hasil pemeriksaan',
                prefixIcon: Icon(Icons.fact_check_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'approved', child: Text('Disetujui')),
                DropdownMenuItem(value: 'rejected', child: Text('Ditolak')),
                DropdownMenuItem(
                  value: 'pending',
                  child: Text('Masih ditinjau'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _status = value);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login_rounded),
              title: const Text('Waktu masuk'),
              subtitle: Text(
                _checkIn == null
                    ? '-'
                    : AppDateFormatter.longDateTime(_checkIn!),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDateTime(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Waktu pulang'),
              subtitle: Text(
                _checkOut == null
                    ? '-'
                    : AppDateFormatter.longDateTime(_checkOut!),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _checkOut == null ? null : () => _editDateTime(false),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Catatan pemeriksaan',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              validator: (value) => (value ?? '').trim().length < 5
                  ? 'Catatan minimal 5 karakter'
                  : null,
            ),
            const SizedBox(height: 18),
            AppButton(
              text: 'Simpan pemeriksaan',
              icon: Icons.check_rounded,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDateTime(bool isCheckIn) async {
    final current = (isCheckIn ? _checkIn : _checkOut) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDate: current,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isCheckIn) {
        _checkIn = value;
      } else {
        _checkOut = value;
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, {
      'review_status': _status,
      'review_notes': _notes.text.trim(),
      if (_checkIn != null) 'check_in_at': _checkIn!.toUtc().toIso8601String(),
      if (_checkOut != null)
        'check_out_at': _checkOut!.toUtc().toIso8601String(),
    });
  }
}

TimeOfDay _parseTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts.first) ?? 0,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

String _formatTime(TimeOfDay value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
