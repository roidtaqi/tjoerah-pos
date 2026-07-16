import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/kitchen_ticket_model.dart';
import '../providers/kds_provider.dart';

class KdsScreen extends ConsumerStatefulWidget {
  const KdsScreen({super.key});

  @override
  ConsumerState<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends ConsumerState<KdsScreen> {
  late final Timer _ticker;
  String _mobileStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(kdsNotifierProvider);
    final station = ref.watch(kdsStationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dapur'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang tiket',
            onPressed: () => ref.invalidate(kdsNotifierProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _StationBar(
            station: station,
            onChanged: (value) {
              ref.read(kdsStationProvider.notifier).setStation(value);
            },
          ),
          Expanded(
            child: tickets.when(
              loading: () =>
                  const AppLoadingState(message: 'Mengambil tiket dapur...'),
              error: (error, _) => AppErrorState(
                message:
                    'Tiket belum dapat diambil dari server. Periksa koneksi dapur.',
                onRetry: () => ref.invalidate(kdsNotifierProvider),
              ),
              data: (data) => _buildBoard(data),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(List<KitchenTicketModel> tickets) {
    final pending = tickets
        .where(
          (ticket) => ticket.status == 'pending' || ticket.status == 'accepted',
        )
        .toList();
    final preparing = tickets
        .where((ticket) => ticket.status == 'preparing')
        .toList();
    final ready = tickets.where((ticket) => ticket.status == 'ready').toList();
    final completed = tickets
        .where((ticket) => ticket.status == 'completed')
        .toList();

    if (AppBreakpoints.isWide(context)) {
      return Padding(
        padding: AppSpacing.page(context),
        child: Column(
          children: [
            _BoardSummary(
              activeCount: pending.length + preparing.length + ready.length,
              completedCount: completed.length,
              onCompletedTap: completed.isEmpty
                  ? null
                  : () => _showCompletedTickets(completed),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _TicketLane(
                      title: 'Menunggu',
                      status: 'pending',
                      color: AppColors.kdsWaiting,
                      tickets: pending,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TicketLane(
                      title: 'Dimasak',
                      status: 'preparing',
                      color: AppColors.kdsCooking,
                      tickets: preparing,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TicketLane(
                      title: 'Siap diambil',
                      status: 'ready',
                      color: AppColors.kdsReady,
                      tickets: ready,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final statusTickets = switch (_mobileStatus) {
      'preparing' => preparing,
      'ready' => ready,
      _ => pending,
    };

    return Padding(
      padding: AppSpacing.page(context),
      child: Column(
        children: [
          SegmentedButton<String>(
            expandedInsets: EdgeInsets.zero,
            segments: [
              ButtonSegment(
                value: 'pending',
                label: Text('Tunggu ${pending.length}'),
              ),
              ButtonSegment(
                value: 'preparing',
                label: Text('Masak ${preparing.length}'),
              ),
              ButtonSegment(
                value: 'ready',
                label: Text('Siap ${ready.length}'),
              ),
            ],
            selected: {_mobileStatus},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() => _mobileStatus = selection.first);
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: statusTickets.isEmpty
                ? const AppEmptyState(
                    title: 'Antrean bersih',
                    message: 'Belum ada tiket pada tahap ini.',
                    icon: Icons.task_alt_rounded,
                  )
                : ListView.separated(
                    itemCount: statusTickets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _TicketCard(ticket: statusTickets[index]),
                  ),
          ),
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showCompletedTickets(completed),
              icon: const Icon(Icons.history_rounded),
              label: Text('${completed.length} tiket selesai'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showCompletedTickets(List<KitchenTicketModel> tickets) {
    return AppBottomSheet.show<void>(
      context,
      title: 'Tiket selesai',
      subtitle: '${tickets.length} tiket pada sesi ini',
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          itemCount: tickets.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final ticket = tickets[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text('#${_shortId(ticket.id)}'),
              subtitle: Text('${ticket.items.length} baris item'),
              trailing: Text(_elapsedLabel(ticket.createdAt)),
            );
          },
        ),
      ),
    );
  }
}

class _StationBar extends StatelessWidget {
  const _StationBar({required this.station, required this.onChanged});

  final String station;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppBreakpoints.isPhone(context) ? 16 : 24,
          vertical: 10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stasiun produksi', style: theme.textTheme.labelLarge),
                  Text(
                    'Tiket diperbarui secara langsung',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'kitchen',
                  icon: Icon(Icons.restaurant_outlined),
                  label: Text('Dapur'),
                ),
                ButtonSegment(
                  value: 'bar',
                  icon: Icon(Icons.local_cafe_outlined),
                  label: Text('Bar'),
                ),
              ],
              selected: {station},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoardSummary extends StatelessWidget {
  const _BoardSummary({
    required this.activeCount,
    required this.completedCount,
    this.onCompletedTap,
  });

  final int activeCount;
  final int completedCount;
  final VoidCallback? onCompletedTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$activeCount tiket aktif',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          onPressed: onCompletedTap,
          icon: const Icon(Icons.history_rounded),
          label: Text('$completedCount selesai'),
        ),
      ],
    );
  }
}

class _TicketLane extends ConsumerWidget {
  const _TicketLane({
    required this.title,
    required this.status,
    required this.color,
    required this.tickets,
  });

  final String title;
  final String status;
  final Color color;
  final List<KitchenTicketModel> tickets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DragTarget<KitchenTicketModel>(
      onAcceptWithDetails: (details) {
        ref
            .read(kdsNotifierProvider.notifier)
            .updateTicketStatus(details.data.id, status);
      },
      builder: (context, candidates, _) {
        final highlighted = candidates.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: highlighted
                ? color.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.45,
                  ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted ? color : theme.colorScheme.outline,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                    AppBadge(
                      text: '${tickets.length}',
                      color: color.withValues(alpha: 0.12),
                      textColor: color,
                    ),
                  ],
                ),
              ),
              Divider(color: theme.colorScheme.outline),
              Expanded(
                child: tickets.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada tiket',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: tickets.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final ticket = tickets[index];
                          return Draggable<KitchenTicketModel>(
                            data: ticket,
                            feedback: SizedBox(
                              width: 320,
                              child: Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(8),
                                child: _TicketCard(ticket: ticket),
                              ),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.35,
                              child: _TicketCard(ticket: ticket),
                            ),
                            child: _TicketCard(ticket: ticket),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket});

  final KitchenTicketModel ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final elapsed = DateTime.now().difference(ticket.createdAt);
    final timerColor = elapsed.inMinutes >= 10
        ? AppColors.error
        : elapsed.inSeconds >= 450
        ? AppColors.warning
        : AppColors.success;
    final urgent = elapsed.inMinutes >= 10 || ticket.priority == 'rush';
    final action = _nextAction(ticket.status);

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: urgent ? timerColor : theme.colorScheme.outline,
          width: urgent ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${_shortId(ticket.id)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (ticket.priority == 'rush') ...[
                  const AppBadge(
                    text: 'SEGERA',
                    color: Color(0xFFFEE2E2),
                    textColor: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                ],
                AppBadge(
                  text: _elapsedLabel(ticket.createdAt),
                  icon: Icons.timer_outlined,
                  color: timerColor.withValues(alpha: 0.12),
                  textColor: timerColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            ...ticket.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${item.qty}x',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: theme.textTheme.titleMedium),
                          if (item.notes?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.notes!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 2),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: () => ref
                      .read(kdsNotifierProvider.notifier)
                      .updateTicketStatus(ticket.id, action.status),
                  icon: Icon(action.icon, size: 19),
                  label: Text(action.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

_TicketAction? _nextAction(String status) => switch (status) {
  'pending' || 'accepted' => const _TicketAction(
    status: 'preparing',
    label: 'Mulai masak',
    icon: Icons.play_arrow_rounded,
  ),
  'preparing' => const _TicketAction(
    status: 'ready',
    label: 'Tandai siap',
    icon: Icons.notifications_active_outlined,
  ),
  'ready' => const _TicketAction(
    status: 'completed',
    label: 'Selesaikan',
    icon: Icons.check_rounded,
  ),
  _ => null,
};

class _TicketAction {
  const _TicketAction({
    required this.status,
    required this.label,
    required this.icon,
  });

  final String status;
  final String label;
  final IconData icon;
}

String _shortId(String id) {
  if (id.length <= 6) return id.toUpperCase();
  return id.substring(0, 6).toUpperCase();
}

String _elapsedLabel(DateTime createdAt) {
  final elapsed = DateTime.now().difference(createdAt);
  final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
