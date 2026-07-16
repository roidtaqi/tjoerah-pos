import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../orders/providers/order_history_provider.dart';
import '../providers/cart_provider.dart';
import '../repositories/order_repository.dart';

Future<void> showPaymentFlow(BuildContext context) async {
  if (MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PaymentScreen()));
    return;
  }

  await AppBottomSheet.show<void>(
    context,
    title: 'Pembayaran',
    subtitle: 'Pilih metode dan konfirmasi jumlah.',
    child: Builder(
      builder: (sheetContext) => SizedBox(
        height: math.min(720, MediaQuery.sizeOf(context).height * 0.82),
        child: _PaymentPanel(
          compact: true,
          onCompleted: (orderId) {
            Navigator.pop(sheetContext);
            _showPaymentSuccess(context, orderId);
          },
        ),
      ),
    ),
  );
}

class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: _PaymentPanel(
        onCompleted: (orderId) async {
          await _showPaymentSuccess(context, orderId);
          if (context.mounted) context.go('/pos');
        },
      ),
    );
  }
}

class _PaymentPanel extends ConsumerStatefulWidget {
  const _PaymentPanel({required this.onCompleted, this.compact = false});

  final ValueChanged<String> onCompleted;
  final bool compact;

  @override
  ConsumerState<_PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends ConsumerState<_PaymentPanel> {
  final _cashController = TextEditingController();
  String _method = 'cash';
  String _secondaryMethod = 'qris';
  bool _splitPayment = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cashController.addListener(_refresh);
  }

  @override
  void dispose() {
    _cashController.removeListener(_refresh);
    _cashController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  double get _cashAmount =>
      double.tryParse(_cashController.text.replaceAll('.', '')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = cart.total;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = !widget.compact && constraints.maxWidth >= 820;
        if (twoColumns) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _OrderSummary(cart: cart)),
              const SizedBox(width: 24),
              Expanded(child: _buildPaymentForm(cart, total)),
            ],
          );
        }

        return SingleChildScrollView(
          padding: widget.compact
              ? const EdgeInsets.fromLTRB(20, 0, 20, 24)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.compact) ...[
                _OrderSummary(cart: cart),
                const SizedBox(height: 20),
              ],
              _buildPaymentForm(cart, total),
            ],
          ),
        );
      },
    );

    if (widget.compact) return content;
    return SafeArea(
      child: Padding(padding: AppSpacing.page(context), child: content),
    );
  }

  Widget _buildPaymentForm(CartState cart, double total) {
    final theme = Theme.of(context);
    final currency = _currency();
    final cash = _cashAmount;
    final secondaryAmount = _splitPayment ? math.max(0, total - cash) : 0.0;
    final change = !_splitPayment && _method == 'cash'
        ? math.max(0, cash - total)
        : 0.0;
    final valid = _splitPayment
        ? cash > 0 && cash < total
        : _method == 'cash'
        ? cash >= total
        : true;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Metode pembayaran',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Tooltip(
                message: 'Bagi pembayaran',
                child: Switch(
                  value: _splitPayment,
                  onChanged: (value) {
                    setState(() {
                      _splitPayment = value;
                      if (value) _method = 'cash';
                    });
                  },
                ),
              ),
            ],
          ),
          Text(
            _splitPayment
                ? 'Gabungkan tunai dengan satu metode non-tunai.'
                : 'Pilih satu metode untuk seluruh tagihan.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (!_splitPayment)
            SegmentedButton<String>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(
                  value: 'cash',
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Tunai'),
                ),
                ButtonSegment(
                  value: 'qris',
                  icon: Icon(Icons.qr_code_2_rounded),
                  label: Text('QRIS'),
                ),
                ButtonSegment(
                  value: 'card',
                  icon: Icon(Icons.credit_card_outlined),
                  label: Text('Kartu'),
                ),
              ],
              selected: {_method},
              onSelectionChanged: (selection) {
                setState(() => _method = selection.first);
              },
              showSelectedIcon: false,
            )
          else
            SegmentedButton<String>(
              expandedInsets: EdgeInsets.zero,
              segments: const [
                ButtonSegment(value: 'qris', label: Text('Tunai + QRIS')),
                ButtonSegment(value: 'card', label: Text('Tunai + Kartu')),
              ],
              selected: {_secondaryMethod},
              onSelectionChanged: (selection) {
                setState(() => _secondaryMethod = selection.first);
              },
              showSelectedIcon: false,
            ),
          if (_method == 'cash' || _splitPayment) ...[
            const SizedBox(height: 18),
            TextField(
              controller: _cashController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: _splitPayment ? 'Bagian tunai' : 'Uang diterima',
                prefixText: 'Rp ',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickAmounts(total)
                    .map(
                      (amount) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(
                            amount == total
                                ? 'Uang pas'
                                : currency.format(amount),
                          ),
                          onPressed: () {
                            _cashController.text = amount.round().toString();
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _PaymentRow(
                  label: 'Total tagihan',
                  value: currency.format(total),
                ),
                if (_splitPayment) ...[
                  const SizedBox(height: 8),
                  _PaymentRow(label: 'Tunai', value: currency.format(cash)),
                  const SizedBox(height: 8),
                  _PaymentRow(
                    label: _secondaryMethod == 'qris' ? 'QRIS' : 'Kartu',
                    value: currency.format(secondaryAmount),
                  ),
                ] else if (_method == 'cash') ...[
                  const SizedBox(height: 8),
                  _PaymentRow(
                    label: 'Kembalian',
                    value: currency.format(change),
                    emphasize: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            text: _isProcessing ? 'Menyimpan...' : 'Konfirmasi pembayaran',
            icon: Icons.check_rounded,
            isLoading: _isProcessing,
            onPressed: valid ? () => _processPayment(cart, cash) : null,
          ),
          if (!valid && (_method == 'cash' || _splitPayment)) ...[
            const SizedBox(height: 8),
            Text(
              _splitPayment
                  ? 'Masukkan bagian tunai yang lebih kecil dari total tagihan.'
                  : 'Jumlah tunai belum mencukupi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<double> _quickAmounts(double total) {
    if (_splitPayment) {
      return [
        (total * 0.25).roundToDouble(),
        (total * 0.5).roundToDouble(),
        (total * 0.75).roundToDouble(),
      ];
    }
    final rounded50 = (total / 50000).ceil() * 50000.0;
    final rounded100 = (total / 100000).ceil() * 100000.0;
    return <double>{
      total,
      rounded50,
      rounded100,
      math.max(200000.0, rounded100).toDouble(),
    }.toList()..sort();
  }

  Future<void> _processPayment(CartState cart, double cash) async {
    setState(() => _isProcessing = true);
    final method = _splitPayment ? 'split' : _method;
    final breakdown = _splitPayment
        ? {
            'cash': cash,
            _secondaryMethod: math.max(0.0, cart.total - cash).toDouble(),
          }
        : {_method: cart.total};

    try {
      final orderId = await OrderRepository().createOrder(
        items: cart.items,
        subtotal: cart.subtotal,
        discount: cart.discount,
        tax: cart.tax,
        total: cart.total,
        orderType: cart.orderType,
        tableId: cart.tableId,
        note: cart.note,
        customerName: cart.customerName,
        paymentMethod: method,
        paymentBreakdown: breakdown,
      );
      ref.invalidate(orderHistoryProvider);
      ref.read(cartProvider.notifier).clearCart();
      if (mounted) widget.onCompleted(orderId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pembayaran belum dapat disimpan: $error')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.cart});

  final CartState cart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = _currency();
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ringkasan pesanan', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${cart.itemCount} item - ${cart.orderTypeLabel}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ...cart.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${item.quantity}x',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(currency.format(item.total)),
                ],
              ),
            ),
          ),
          Divider(color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          _PaymentRow(label: 'Subtotal', value: currency.format(cart.subtotal)),
          if (cart.discount > 0) ...[
            const SizedBox(height: 8),
            _PaymentRow(
              label: 'Diskon',
              value: '-${currency.format(cart.discount)}',
            ),
          ],
          const SizedBox(height: 8),
          _PaymentRow(label: 'Pajak 11%', value: currency.format(cart.tax)),
          const SizedBox(height: 14),
          _PaymentRow(
            label: 'Total',
            value: currency.format(cart.total),
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(value, style: style?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

NumberFormat _currency() =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

Future<void> _showPaymentSuccess(BuildContext context, String orderId) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.check_rounded,
          color: Color(0xFF15803D),
          size: 30,
        ),
      ),
      title: const Text('Pembayaran tersimpan'),
      content: Text(
        'Pesanan #${orderId.substring(0, 8).toUpperCase()} siap diproses. Data akan disinkronkan otomatis.',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Pesanan baru'),
        ),
      ],
    ),
  );
}
