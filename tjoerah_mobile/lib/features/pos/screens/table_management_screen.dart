import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/table_models.dart';
import '../providers/table_provider.dart';

class TableManagementScreen extends ConsumerStatefulWidget {
  const TableManagementScreen({super.key});

  @override
  ConsumerState<TableManagementScreen> createState() =>
      _TableManagementScreenState();
}

class _TableManagementScreenState extends ConsumerState<TableManagementScreen> {
  final Map<String, Offset> _draftPositions = {};
  final Set<String> _savingPositions = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atur meja & area'),
        actions: [
          IconButton(
            tooltip: 'Tambah area',
            onPressed: () => _showFloorForm(),
            icon: const Icon(Icons.add_business_outlined),
          ),
          IconButton(
            tooltip: 'Sinkronkan meja',
            onPressed: _sync,
            icon: const Icon(Icons.sync_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: state.when(
        loading: () => const AppLoadingState(message: 'Menyiapkan denah...'),
        error: (error, _) => AppErrorState(
          message: 'Pengaturan meja belum dapat dibaca.',
          onRetry: () => ref.read(tableProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(TableState state) {
    if (state.floors.isEmpty) {
      return AppEmptyState(
        title: 'Belum ada area meja',
        message: 'Buat area pertama untuk mulai menyusun meja.',
        icon: Icons.table_restaurant_outlined,
        actionLabel: 'Tambah area',
        onAction: () => _showFloorForm(),
      );
    }

    final selectedFloor = state.floors.firstWhere(
      (floor) => floor.id == state.selectedFloorId,
      orElse: () => state.floors.first,
    );
    final tables = state.tables
        .where((table) => table.floorId == selectedFloor.id)
        .toList();

    return SafeArea(
      child: Padding(
        padding: AppSpacing.page(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.floors.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final floor = state.floors[index];
                        return ChoiceChip(
                          label: Text(floor.name),
                          selected: floor.id == selectedFloor.id,
                          showCheckmark: false,
                          onSelected: (_) => ref
                              .read(tableProvider.notifier)
                              .selectFloor(floor.id),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Tambah area',
                  onPressed: () => _showFloorForm(),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedFloor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${tables.length} meja',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit area',
                  onPressed: () => _showFloorForm(floor: selectedFloor),
                  icon: const Icon(Icons.edit_outlined),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => _showTableForm(
                    floors: state.floors,
                    initialFloorId: selectedFloor.id,
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah meja'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _FloorCanvas(
                  tables: tables,
                  width: math.max(640, constraints.maxWidth),
                  height: math.max(460, constraints.maxHeight),
                  positions: _draftPositions,
                  savingPositions: _savingPositions,
                  onMove: _moveTable,
                  onMoveEnd: _savePosition,
                  onEdit: (table) => _showTableForm(
                    table: table,
                    floors: state.floors,
                    initialFloorId: selectedFloor.id,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveTable(DiningTableModel table, Offset delta, Size canvasSize) {
    final current =
        _draftPositions[table.id] ?? Offset(table.positionX, table.positionY);
    setState(() {
      _draftPositions[table.id] = Offset(
        (current.dx + delta.dx).clamp(0, canvasSize.width - 112),
        (current.dy + delta.dy).clamp(0, canvasSize.height - 76),
      );
    });
  }

  Future<void> _savePosition(DiningTableModel table) async {
    final position = _draftPositions[table.id];
    if (position == null) return;
    setState(() => _savingPositions.add(table.id));
    try {
      await ref
          .read(tableProvider.notifier)
          .updateTablePosition(table.id, position.dx, position.dy);
    } finally {
      if (mounted) setState(() => _savingPositions.remove(table.id));
    }
  }

  Future<void> _sync() async {
    try {
      await ref.read(tableProvider.notifier).syncFromServer();
      _draftPositions.clear();
      if (mounted) _showMessage('Denah meja berhasil disinkronkan.');
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    }
  }

  Future<void> _showFloorForm({FloorModel? floor}) async {
    final hasTables =
        floor != null &&
        (ref
                .read(tableProvider)
                .value
                ?.tables
                .any((table) => table.floorId == floor.id) ??
            false);
    final result = await showDialog<_FloorFormResult>(
      context: context,
      builder: (_) => _FloorFormDialog(floor: floor, hasTables: hasTables),
    );
    if (result == null) return;

    try {
      final notifier = ref.read(tableProvider.notifier);
      if (result.delete && floor != null) {
        await notifier.deleteFloor(floor);
        _showMessage('Area berhasil dihapus.');
      } else if (floor == null) {
        await notifier.createFloor(result.name);
        _showMessage('Area baru berhasil dibuat.');
      } else {
        await notifier.updateFloor(floor, result.name);
        _showMessage('Nama area berhasil diperbarui.');
      }
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    }
  }

  Future<void> _showTableForm({
    DiningTableModel? table,
    required List<FloorModel> floors,
    required String initialFloorId,
  }) async {
    final result = await showDialog<_TableFormResult>(
      context: context,
      builder: (_) => _TableFormDialog(
        table: table,
        floors: floors,
        initialFloorId: initialFloorId,
      ),
    );
    if (result == null) return;

    try {
      final notifier = ref.read(tableProvider.notifier);
      if (result.delete && table != null) {
        await notifier.deleteTable(table);
        _draftPositions.remove(table.id);
        _showMessage('Meja berhasil dihapus.');
      } else if (table == null) {
        await notifier.createTable(
          floorId: result.floorId,
          name: result.name,
          capacity: result.capacity,
          status: result.status,
        );
        _showMessage('Meja baru berhasil ditambahkan.');
      } else {
        await notifier.updateTable(
          table: table,
          floorId: result.floorId,
          name: result.name,
          capacity: result.capacity,
          status: result.status,
        );
        _showMessage('Meja berhasil diperbarui.');
      }
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _errorMessage(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '');
}

class _FloorCanvas extends StatelessWidget {
  const _FloorCanvas({
    required this.tables,
    required this.width,
    required this.height,
    required this.positions,
    required this.savingPositions,
    required this.onMove,
    required this.onMoveEnd,
    required this.onEdit,
  });

  final List<DiningTableModel> tables;
  final double width;
  final double height;
  final Map<String, Offset> positions;
  final Set<String> savingPositions;
  final void Function(DiningTableModel, Offset, Size) onMove;
  final ValueChanged<DiningTableModel> onMoveEnd;
  final ValueChanged<DiningTableModel> onEdit;

  @override
  Widget build(BuildContext context) {
    final canvasSize = Size(width, height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InteractiveViewer(
          constrained: false,
          minScale: 0.65,
          maxScale: 1.8,
          boundaryMargin: const EdgeInsets.all(80),
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _GridPainter(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              child: tables.isEmpty
                  ? const Center(
                      child: AppEmptyState(
                        title: 'Area masih kosong',
                        message: 'Tambahkan meja untuk area ini.',
                        icon: Icons.add_box_outlined,
                      ),
                    )
                  : Stack(
                      children: tables.map((table) {
                        final raw =
                            positions[table.id] ??
                            Offset(table.positionX, table.positionY);
                        final position = Offset(
                          raw.dx.clamp(0, width - 112),
                          raw.dy.clamp(0, height - 76),
                        );
                        return Positioned(
                          left: position.dx,
                          top: position.dy,
                          child: _EditableTable(
                            table: table,
                            saving: savingPositions.contains(table.id),
                            onPanUpdate: (delta) =>
                                onMove(table, delta, canvasSize),
                            onPanEnd: () => onMoveEnd(table),
                            onTap: () => onEdit(table),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditableTable extends StatelessWidget {
  const _EditableTable({
    required this.table,
    required this.saving,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onTap,
  });

  final DiningTableModel table;
  final bool saving;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(table.status);
    return Semantics(
      button: true,
      label: '${table.name}, ${table.capacity} kursi',
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) => onPanUpdate(details.delta),
        onPanEnd: (_) => onPanEnd(),
        child: Container(
          width: 112,
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_restaurant_outlined, size: 18, color: color),
                  const Spacer(),
                  if (saving)
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.drag_indicator_rounded, size: 17, color: color),
                ],
              ),
              const Spacer(),
              Text(
                table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${table.capacity} kursi',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloorFormDialog extends StatefulWidget {
  const _FloorFormDialog({required this.floor, required this.hasTables});

  final FloorModel? floor;
  final bool hasTables;

  @override
  State<_FloorFormDialog> createState() => _FloorFormDialogState();
}

class _FloorFormDialogState extends State<_FloorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.floor?.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.floor != null;
    return AlertDialog(
      title: Text(editing ? 'Edit area' : 'Tambah area'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama area',
            hintText: 'Contoh: Lantai 1 atau Teras',
            prefixIcon: Icon(Icons.layers_outlined),
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Nama area wajib diisi' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        if (editing && !widget.hasTables)
          IconButton(
            tooltip: 'Hapus area',
            onPressed: () => Navigator.pop(
              context,
              _FloorFormResult(name: widget.floor!.name, delete: true),
            ),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, _FloorFormResult(name: _nameController.text.trim()));
  }
}

class _TableFormDialog extends StatefulWidget {
  const _TableFormDialog({
    required this.table,
    required this.floors,
    required this.initialFloorId,
  });

  final DiningTableModel? table;
  final List<FloorModel> floors;
  final String initialFloorId;

  @override
  State<_TableFormDialog> createState() => _TableFormDialogState();
}

class _TableFormDialogState extends State<_TableFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late String _floorId;
  late String _status;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.table?.name);
    _capacityController = TextEditingController(
      text: (widget.table?.capacity ?? 2).toString(),
    );
    _floorId = widget.table?.floorId ?? widget.initialFloorId;
    _status = widget.table?.status ?? 'available';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.table != null;
    return AlertDialog(
      title: Text(editing ? 'Edit meja' : 'Tambah meja'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama meja',
                    hintText: 'Contoh: Meja 01',
                    prefixIcon: Icon(Icons.table_restaurant_outlined),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Nama meja wajib diisi'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Kapasitas',
                    suffixText: 'kursi',
                    prefixIcon: Icon(Icons.people_outline_rounded),
                  ),
                  validator: (value) {
                    final capacity = int.tryParse(value ?? '');
                    return capacity == null || capacity < 1
                        ? 'Kapasitas minimal 1 kursi'
                        : null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _floorId,
                  decoration: const InputDecoration(
                    labelText: 'Area',
                    prefixIcon: Icon(Icons.layers_outlined),
                  ),
                  items: widget.floors
                      .map(
                        (floor) => DropdownMenuItem(
                          value: floor.id,
                          child: Text(floor.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => _floorId = value ?? _floorId,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    prefixIcon: Icon(Icons.info_outline_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'available',
                      child: Text('Tersedia'),
                    ),
                    DropdownMenuItem(value: 'reserved', child: Text('Dipesan')),
                    DropdownMenuItem(
                      value: 'cleaning',
                      child: Text('Dibersihkan'),
                    ),
                    DropdownMenuItem(value: 'occupied', child: Text('Terisi')),
                  ],
                  onChanged: (value) => _status = value ?? _status,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (editing && widget.table!.status != 'occupied')
          IconButton(
            tooltip: 'Hapus meja',
            onPressed: () => Navigator.pop(
              context,
              _TableFormResult(
                name: widget.table!.name,
                floorId: _floorId,
                capacity: widget.table!.capacity,
                status: widget.table!.status,
                delete: true,
              ),
            ),
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Simpan')),
      ],
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      _TableFormResult(
        name: _nameController.text.trim(),
        floorId: _floorId,
        capacity: int.parse(_capacityController.text),
        status: _status,
      ),
    );
  }
}

class _FloorFormResult {
  const _FloorFormResult({required this.name, this.delete = false});

  final String name;
  final bool delete;
}

class _TableFormResult {
  const _TableFormResult({
    required this.name,
    required this.floorId,
    required this.capacity,
    required this.status,
    this.delete = false,
  });

  final String name;
  final String floorId;
  final int capacity;
  final String status;
  final bool delete;
}

Color _statusColor(String status) => switch (status) {
  'occupied' => AppColors.error,
  'reserved' => AppColors.info,
  'cleaning' => AppColors.warning,
  _ => AppColors.success,
};

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (double x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.color != color;
}
