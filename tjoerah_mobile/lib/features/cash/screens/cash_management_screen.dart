import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../attendance/screens/attendance_camera_screen.dart';
import '../models/cash_model.dart';
import '../providers/cash_provider.dart';

class CashManagementScreen extends ConsumerWidget {
  const CashManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cash = ref.watch(cashProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kas outlet'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(cashProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: cash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: _cleanError(error),
          onRetry: () => ref.read(cashProvider.notifier).refresh(),
        ),
        data: (overview) => RefreshIndicator(
          onRefresh: () => ref.read(cashProvider.notifier).refresh(),
          child: ListView(
            padding: AppSpacing.page(context),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: overview.currentShift == null
                      ? _ClosedCashView(overview: overview)
                      : _OpenCashView(
                          overview: overview,
                          shift: overview.currentShift!,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedCashView extends ConsumerWidget {
  const _ClosedCashView({required this.overview});

  final CashOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.point_of_sale_outlined,
                size: 34,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text('Kas belum dibuka', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                overview.outletName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                text: 'Buka kas',
                icon: Icons.lock_open_outlined,
                onPressed: () => _showOpenDialog(context, ref),
              ),
            ],
          ),
        ),
        if (overview.recentShifts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Riwayat sesi', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _ShiftHistory(shifts: overview.recentShifts),
        ],
      ],
    );
  }
}

class _OpenCashView extends ConsumerWidget {
  const _OpenCashView({required this.overview, required this.shift});

  final CashOverview overview;
  final CashShift shift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = shift.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kas aktif', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${overview.outletName} - ${shift.openedBy ?? 'Pengguna'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _showCloseDialog(context, ref, shift),
              icon: const Icon(Icons.lock_outline_rounded),
              label: const Text('Tutup kas'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  height: 112,
                  child: AppMetricCard(
                    title: 'Saldo sistem',
                    value: _currency(summary.expectedCash),
                    icon: Icons.account_balance_wallet_outlined,
                    iconColor: AppColors.success,
                  ),
                ),
                SizedBox(
                  width: width,
                  height: 112,
                  child: AppMetricCard(
                    title: 'Total masuk',
                    value: _currency(summary.totalIn),
                    icon: Icons.south_west_rounded,
                    iconColor: AppColors.info,
                  ),
                ),
                SizedBox(
                  width: width,
                  height: 112,
                  child: AppMetricCard(
                    title: 'Total keluar',
                    value: _currency(summary.totalOut),
                    icon: Icons.north_east_rounded,
                    iconColor: AppColors.warning,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _showMovementDialog(
                  context,
                  ref,
                  type: 'cash_in',
                  canAdjust: overview.canAdjust,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Uang masuk'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showMovementDialog(
                  context,
                  ref,
                  type: 'cash_out',
                  canAdjust: overview.canAdjust,
                ),
                icon: const Icon(Icons.remove_rounded),
                label: const Text('Uang keluar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Pergerakan kas', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        AppCard(
          padding: EdgeInsets.zero,
          child: shift.movements.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Belum ada pergerakan kas.')),
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < shift.movements.length;
                      index++
                    ) ...[
                      _MovementTile(movement: shift.movements[index]),
                      if (index != shift.movements.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
        ),
        if (overview.recentShifts.where((item) => !item.isOpen).isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Sesi sebelumnya', style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          _ShiftHistory(
            shifts: overview.recentShifts
                .where((item) => !item.isOpen)
                .toList(),
          ),
        ],
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = movement.isOut ? AppColors.error : AppColors.success;
    return ListTile(
      minLeadingWidth: 36,
      leading: Icon(
        movement.isOut ? Icons.north_east_rounded : Icons.south_west_rounded,
        color: color,
      ),
      title: Text(_categoryLabel(movement.category)),
      subtitle: Text(
        [
          if (movement.note != null && movement.note!.isNotEmpty)
            movement.note!,
          _cashDate(movement.occurredAt),
          if (movement.userName != null) movement.userName!,
        ].join(' - '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (movement.hasEvidence) ...[
            Icon(Icons.attach_file_rounded, size: 17, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            '${movement.isOut ? '-' : '+'}${_currency(movement.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ShiftHistory extends StatelessWidget {
  const _ShiftHistory({required this.shifts});

  final List<CashShift> shifts;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < shifts.length; index++) ...[
            ExpansionTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(shifts[index].openedBy ?? shifts[index].number),
              subtitle: Text(_cashDate(shifts[index].startedAt, year: true)),
              trailing: Text(_currency(shifts[index].summary.expectedCash)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      _SummaryLine(
                        label: 'Saldo sistem',
                        value: _currency(shifts[index].summary.expectedCash),
                      ),
                      if (shifts[index].summary.closingCash != null)
                        _SummaryLine(
                          label: 'Uang fisik',
                          value: _currency(shifts[index].summary.closingCash!),
                        ),
                      if (shifts[index].summary.difference != null)
                        _SummaryLine(
                          label: 'Selisih',
                          value: _currency(shifts[index].summary.difference!),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (index != shifts.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 38),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showOpenDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final value = await showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Buka kas'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Uang awal',
            prefixText: 'Rp ',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
          validator: (raw) => double.tryParse(raw ?? '') == null
              ? 'Masukkan jumlah uang awal'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(dialogContext, double.parse(controller.text));
          },
          child: const Text('Buka kas'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null || !context.mounted) return;
  await _runAction(
    context,
    () => ref.read(cashProvider.notifier).openShift(value),
    'Kas berhasil dibuka.',
  );
}

Future<void> _showMovementDialog(
  BuildContext context,
  WidgetRef ref, {
  required String type,
  required bool canAdjust,
}) async {
  final draft = await showDialog<_MovementDraft>(
    context: context,
    builder: (_) => _MovementDialog(type: type, canAdjust: canAdjust),
  );
  if (draft == null || !context.mounted) return;
  await _runAction(
    context,
    () => ref
        .read(cashProvider.notifier)
        .addMovement(
          type: draft.type,
          category: draft.category,
          amount: draft.amount,
          note: draft.note,
          photoPath: draft.photoPath,
        ),
    'Pergerakan kas berhasil dicatat.',
  );
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({required this.type, required this.canAdjust});

  final String type;
  final bool canAdjust;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _type = widget.type;
  late String _category = _categories(widget.type).first.$1;
  String? _photoPath;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = _categories(_type);
    return AlertDialog(
      title: Text(
        _type.endsWith('out') ? 'Catat uang keluar' : 'Catat uang masuk',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.canAdjust)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Transaksi')),
                      ButtonSegment(value: true, label: Text('Koreksi')),
                    ],
                    selected: {_type.startsWith('adjustment_')},
                    onSelectionChanged: (selection) {
                      final adjustment = selection.first;
                      setState(() {
                        _type = adjustment
                            ? (widget.type.endsWith('out')
                                  ? 'adjustment_out'
                                  : 'adjustment_in')
                            : widget.type;
                        _category = _categories(_type).first.$1;
                      });
                    },
                    showSelectedIcon: false,
                  ),
                if (widget.canAdjust) const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: options.any((item) => item.$1 == _category)
                      ? _category
                      : options.first.$1,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: options
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.$1,
                          child: Text(item.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Jumlah',
                    prefixText: 'Rp ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (raw) {
                    final value = double.tryParse(raw ?? '');
                    return value == null || value <= 0
                        ? 'Jumlah wajib lebih dari 0'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan',
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                  validator: (raw) => (raw ?? '').trim().length < 3
                      ? 'Keterangan minimal 3 karakter'
                      : null,
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _takePhoto,
                  icon: Icon(
                    _photoPath == null
                        ? Icons.add_a_photo_outlined
                        : Icons.check_circle_outline_rounded,
                  ),
                  label: Text(
                    _photoPath == null ? 'Tambah bukti foto' : 'Foto terlampir',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _MovementDraft(
                type: _type,
                category: _category,
                amount: double.parse(_amount.text),
                note: _note.text.trim(),
                photoPath: _photoPath,
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Simpan'),
        ),
      ],
    );
  }

  Future<void> _takePhoto() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const AttendanceCameraScreen(
          actionLabel: 'Bukti transaksi kas',
          preferredLensDirection: CameraLensDirection.back,
        ),
      ),
    );
    if (path != null && mounted) setState(() => _photoPath = path);
  }
}

class _MovementDraft {
  const _MovementDraft({
    required this.type,
    required this.category,
    required this.amount,
    required this.note,
    this.photoPath,
  });

  final String type;
  final String category;
  final double amount;
  final String note;
  final String? photoPath;
}

Future<void> _showCloseDialog(
  BuildContext context,
  WidgetRef ref,
  CashShift shift,
) async {
  final draft = await showDialog<(double, String?)>(
    context: context,
    builder: (_) => _CloseCashDialog(expected: shift.summary.expectedCash),
  );
  if (draft == null || !context.mounted) return;
  await _runAction(
    context,
    () => ref
        .read(cashProvider.notifier)
        .closeShift(shiftId: shift.id, closingCash: draft.$1, note: draft.$2),
    'Kas berhasil ditutup.',
  );
}

class _CloseCashDialog extends StatefulWidget {
  const _CloseCashDialog({required this.expected});

  final double expected;

  @override
  State<_CloseCashDialog> createState() => _CloseCashDialogState();
}

class _CloseCashDialogState extends State<_CloseCashDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  double? get _value => double.tryParse(_amount.text);
  double get _difference => (_value ?? widget.expected) - widget.expected;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_refresh);
  }

  @override
  void dispose() {
    _amount.removeListener(_refresh);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasDifference = _value != null && _difference.abs() >= 0.01;
    return AlertDialog(
      title: const Text('Tutup kas'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SummaryLine(
                label: 'Saldo sistem',
                value: _currency(widget.expected),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Uang fisik',
                  prefixText: 'Rp ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (raw) => double.tryParse(raw ?? '') == null
                    ? 'Masukkan hasil hitung uang fisik'
                    : null,
              ),
              if (_value != null) ...[
                const SizedBox(height: 10),
                _SummaryLine(label: 'Selisih', value: _currency(_difference)),
              ],
              if (hasDifference) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Penjelasan selisih',
                    prefixIcon: Icon(Icons.notes_rounded),
                    alignLabelWithHint: true,
                  ),
                  validator: (raw) => (raw ?? '').trim().length < 3
                      ? 'Jelaskan penyebab selisih'
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              _value!,
              hasDifference ? _note.text.trim() : null,
            ));
          },
          child: const Text('Tutup kas'),
        ),
      ],
    );
  }
}

Future<void> _runAction(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_cleanError(error))));
  }
}

List<(String, String)> _categories(String type) {
  if (type.startsWith('adjustment_')) {
    return const [('cash_correction', 'Koreksi saldo kas')];
  }
  if (type == 'cash_out') {
    return const [
      ('urgent_purchase', 'Pembelian mendesak'),
      ('petty_cash', 'Biaya operasional kecil'),
      ('supplier', 'Pembayaran pemasok'),
      ('bank_deposit', 'Setoran bank'),
      ('other_out', 'Pengeluaran lainnya'),
    ];
  }
  return const [
    ('change_fund', 'Tambahan uang kembalian'),
    ('owner_deposit', 'Setoran owner'),
    ('customer_debt', 'Pelunasan pelanggan'),
    ('other_in', 'Pemasukan lainnya'),
  ];
}

String _categoryLabel(String category) {
  for (final type in const [
    'cash_in',
    'cash_out',
    'adjustment_in',
    'adjustment_out',
  ]) {
    for (final item in _categories(type)) {
      if (item.$1 == category) return item.$2;
    }
  }
  return switch (category) {
    'opening_cash' => 'Saldo awal',
    'cash_sale' => 'Penjualan tunai',
    'customer_refund' => 'Refund pelanggan',
    'cash_reconciliation' => 'Rekonsiliasi kas',
    _ => category.replaceAll('_', ' '),
  };
}

String _currency(double value) => NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
).format(value);

String _cashDate(DateTime value, {bool year = false}) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final local = value.toLocal();
  final date =
      '${local.day.toString().padLeft(2, '0')} '
      '${months[local.month - 1]}${year ? ' ${local.year}' : ''}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date, $time';
}

String _cleanError(Object error) => error
    .toString()
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Exception: ', '');
