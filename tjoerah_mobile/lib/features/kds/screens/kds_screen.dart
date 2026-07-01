import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/kds_provider.dart';
import '../models/kitchen_ticket_model.dart';

class KdsScreen extends StatefulWidget {
  const KdsScreen({super.key});

  @override
  State<KdsScreen> createState() => _KdsScreenState();
}

class _KdsScreenState extends State<KdsScreen> {
  late Timer _tickerTimer;

  @override
  void initState() {
    super.initState();
    // Refresh SLA timers every second
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tickerTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => KdsProvider(),
      child: Consumer<KdsProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Row(
                children: [
                  const Icon(Icons.soup_kitchen, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Text('Kitchen Display System', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 24),
                  // Station toggle
                  DropdownButton<String>(
                    value: provider.selectedStation,
                    items: const [
                      DropdownMenuItem(value: 'kitchen', child: Text('Kitchen Station')),
                      DropdownMenuItem(value: 'bar', child: Text('Bar Station')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        provider.setStation(val);
                      }
                    },
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    underline: const SizedBox(),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => provider.fetchTickets(),
                  tooltip: 'Manual Refresh',
                ),
              ],
            ),
            body: provider.isLoading && provider.tickets.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildKanbanBoard(context, provider),
          );
        },
      ),
    );
  }

  Widget _buildKanbanBoard(BuildContext context, KdsProvider provider) {
    final tickets = provider.tickets;
    
    // Group tickets by status columns
    final pending = tickets.where((t) => t.status == 'pending' || t.status == 'accepted').toList();
    final preparing = tickets.where((t) => t.status == 'preparing').toList();
    final ready = tickets.where((t) => t.status == 'ready').toList();
    final completed = tickets.where((t) => t.status == 'completed').toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(child: _buildColumn(context, 'Pending', pending, 'pending', provider)),
          const SizedBox(width: 16),
          Expanded(child: _buildColumn(context, 'Preparing', preparing, 'preparing', provider)),
          const SizedBox(width: 16),
          Expanded(child: _buildColumn(context, 'Ready / Pickup', ready, 'ready', provider)),
          const SizedBox(width: 16),
          Expanded(child: _buildColumn(context, 'Completed', completed, 'completed', provider)),
        ],
      ),
    );
  }

  Widget _buildColumn(
    BuildContext context,
    String title,
    List<KitchenTicketModel> list,
    String statusKey,
    KdsProvider provider,
  ) {
    return DragTarget<KitchenTicketModel>(
      onAcceptWithDetails: (details) {
        provider.updateTicketStatus(details.data.id, statusKey);
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isOver ? Colors.grey[200] : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isOver ? AppColors.accent : AppColors.border, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${list.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: AppColors.border),
              
              // Tickets List
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                          'No tickets',
                          style: TextStyle(color: Colors.grey[400], fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final ticket = list[index];
                          return Draggable<KitchenTicketModel>(
                            data: ticket,
                            feedback: SizedBox(
                              width: MediaQuery.of(context).size.width / 4 - 32,
                              child: _buildTicketCard(context, ticket, provider, isFeedback: true),
                            ),
                            childWhenDragging: Opacity(
                              opacity: 0.4,
                              child: _buildTicketCard(context, ticket, provider),
                            ),
                            child: _buildTicketCard(context, ticket, provider),
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

  Widget _buildTicketCard(
    BuildContext context,
    KitchenTicketModel ticket,
    KdsProvider provider, {
    bool isFeedback = false,
  }) {
    // 10 minutes default SLA
    const slaSeconds = 600; 
    final elapsedSeconds = DateTime.now().difference(ticket.createdAt).inSeconds;
    
    Color cardBorderColor = AppColors.border;
    Color timerColor = Colors.green;
    bool isUrgent = false;

    // SLA Warning thresholds
    if (elapsedSeconds < slaSeconds * 0.75) {
      timerColor = Colors.green;
    } else if (elapsedSeconds < slaSeconds) {
      timerColor = Colors.orange;
      cardBorderColor = Colors.orange;
    } else {
      timerColor = Colors.red;
      cardBorderColor = Colors.red;
      isUrgent = true;
    }

    if (ticket.priority == 'rush') {
      cardBorderColor = Colors.redAccent;
      isUrgent = true;
    }

    // Format SLA minutes/seconds
    final minutes = elapsedSeconds ~/ 60;
    final seconds = elapsedSeconds % 60;
    final timeStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Card(
      elevation: isFeedback ? 8 : 2,
      margin: const EdgeInsets.symmetric(vertical: 6.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor, width: isUrgent ? 2 : 1),
      ),
      child: InkWell(
        onTap: () {
          // Tap to advance state
          final nextStatus = _getNextStatus(ticket.status);
          if (nextStatus != null) {
            provider.updateTicketStatus(ticket.id, nextStatus);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ticket Metadata Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ticket #${ticket.id.substring(0, 4).toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Row(
                    children: [
                      if (ticket.priority == 'rush' || ticket.priority == 'vip')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: ticket.priority == 'rush' ? Colors.red : Colors.purple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ticket.priority.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Text(
                        timeStr,
                        style: TextStyle(color: timerColor, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Items List
              ...ticket.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.qty}x ',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                              ),
                              if (item.notes != null && item.notes!.isNotEmpty)
                                Text(
                                  'Note: ${item.notes}',
                                  style: const TextStyle(color: Colors.red, fontSize: 11, fontStyle: FontStyle.italic),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String? _getNextStatus(String currentStatus) {
    switch (currentStatus) {
      case 'pending':
      case 'accepted':
        return 'preparing';
      case 'preparing':
        return 'ready';
      case 'ready':
        return 'completed';
      default:
        return null;
    }
  }
}
