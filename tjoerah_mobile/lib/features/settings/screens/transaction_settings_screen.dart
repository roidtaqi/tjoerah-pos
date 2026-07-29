import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../models/transaction_settings.dart';
import '../providers/transaction_settings_provider.dart';

class TransactionSettingsScreen extends ConsumerWidget {
  const TransactionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(transactionSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pajak transaksi')),
      body: settings.when(
        loading: () =>
            const AppLoadingState(message: 'Memuat pengaturan pajak...'),
        error: (_, _) => AppErrorState(
          message: 'Pengaturan pajak belum dapat dimuat.',
          onRetry: () =>
              ref.read(transactionSettingsProvider.notifier).refresh(),
        ),
        data: (value) => _TaxForm(settings: value),
      ),
    );
  }
}

class _TaxForm extends ConsumerStatefulWidget {
  const _TaxForm({required this.settings});

  final TransactionSettings settings;

  @override
  ConsumerState<_TaxForm> createState() => _TaxFormState();
}

class _TaxFormState extends ConsumerState<_TaxForm> {
  late bool _enabled;
  late final TextEditingController _rate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settings.taxEnabled;
    _rate = TextEditingController(text: _formatRate(widget.settings.taxRate));
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: AppSpacing.page(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _enabled,
                      title: const Text('Kenakan pajak'),
                      subtitle: const Text(
                        'Pajak dihitung dari subtotal setelah diskon.',
                      ),
                      secondary: const Icon(Icons.receipt_long_outlined),
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _rate,
                        enabled: _enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d{0,3}([.,]\d{0,2})?'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Tarif pajak',
                          suffixText: '%',
                          prefixIcon: Icon(Icons.percent_rounded),
                          helperText: 'Nilai yang diizinkan 0 sampai 100%.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _enabled
                    ? 'Contoh: subtotal setelah diskon Rp 100.000 dengan tarif ${_rate.text}% menghasilkan pajak sesuai tarif tersebut.'
                    : 'Pajak dinonaktifkan untuk transaksi baru.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              AppButton(
                text: _saving ? 'Menyimpan...' : 'Simpan pengaturan',
                icon: Icons.save_outlined,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final value = double.tryParse(_rate.text.replaceAll(',', '.'));
    if (_enabled && (value == null || value < 0 || value > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan tarif antara 0 dan 100%.')),
      );
      return;
    }

    setState(() => _saving = true);
    final error = await ref
        .read(transactionSettingsProvider.notifier)
        .updateTax(enabled: _enabled, rate: value ?? 0);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Pengaturan pajak berhasil disimpan.'),
        backgroundColor: error == null
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

String _formatRate(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';
