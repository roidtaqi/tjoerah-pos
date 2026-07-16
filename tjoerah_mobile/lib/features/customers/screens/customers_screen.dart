import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_metric_card.dart';
import '../../../shared/components/app_search_bar.dart';
import '../../pos/providers/cart_provider.dart';
import '../models/customer_model.dart';
import '../providers/customer_provider.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _query = '';
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          IconButton(
            tooltip: 'Tambah pelanggan',
            onPressed: _addCustomer,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: () => ref.read(customerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: customers.when(
        loading: () => const AppLoadingState(message: 'Memuat pelanggan...'),
        error: (error, _) => AppErrorState(
          message: 'Data pelanggan belum tersedia di perangkat ini.',
          onRetry: () => ref.read(customerProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<CustomerModel> customers) {
    final query = _query.trim().toLowerCase();
    final filtered = customers.where((customer) {
      return query.isEmpty ||
          customer.name.toLowerCase().contains(query) ||
          (customer.phone?.toLowerCase().contains(query) ?? false) ||
          (customer.email?.toLowerCase().contains(query) ?? false);
    }).toList();
    final pending = customers.where((customer) => !customer.isSynced).length;
    final returning = customers
        .where((customer) => customer.visitCount > 1)
        .length;

    return RefreshIndicator(
      onRefresh: () => ref.read(customerProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page(context),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    height: 112,
                    child: AppMetricCard(
                      title: 'Total pelanggan',
                      value: '${customers.length}',
                      icon: Icons.people_outline_rounded,
                      iconColor: AppColors.info,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    height: 112,
                    child: AppMetricCard(
                      title: 'Pelanggan kembali',
                      value: '$returning',
                      icon: Icons.loyalty_outlined,
                      iconColor: AppColors.success,
                    ),
                  ),
                  if (columns == 3)
                    SizedBox(
                      width: width,
                      height: 112,
                      child: AppMetricCard(
                        title: 'Antrean sinkron',
                        value: '$pending',
                        icon: Icons.cloud_upload_outlined,
                        iconColor: pending == 0
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          AppSearchBar(
            hintText: 'Cari nama, nomor telepon, atau email',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            AppEmptyState(
              title: customers.isEmpty
                  ? 'Belum ada pelanggan'
                  : 'Pelanggan tidak ditemukan',
              message: customers.isEmpty
                  ? 'Tambahkan pelanggan untuk mulai mencatat kunjungan.'
                  : 'Periksa kembali kata pencarian.',
              icon: Icons.people_outline_rounded,
              onAction: customers.isEmpty ? _addCustomer : null,
              actionLabel: customers.isEmpty ? 'Tambah pelanggan' : null,
            )
          else
            ...filtered.map(
              (customer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CustomerRow(
                  customer: customer,
                  value: _currency.format(customer.totalSpent),
                  onTap: () => _showCustomer(customer),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addCustomer() async {
    final draft = await AppBottomSheet.show<CustomerDraft>(
      context,
      title: 'Pelanggan baru',
      subtitle: 'Nama wajib diisi',
      child: const _CustomerForm(),
    );
    if (draft == null || !mounted) return;

    final synced = await ref.read(customerProvider.notifier).addCustomer(draft);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? '${draft.name} berhasil ditambahkan.'
              : '${draft.name} tersimpan dan menunggu sinkron.',
        ),
      ),
    );
  }

  void _showCustomer(CustomerModel customer) {
    AppBottomSheet.show<void>(
      context,
      title: customer.name,
      subtitle: customer.phone ?? customer.email ?? 'Tanpa kontak',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!customer.isSynced)
              const Align(
                alignment: Alignment.centerLeft,
                child: AppBadge(
                  text: 'Menunggu sinkron',
                  color: AppColors.warningSoft,
                  textColor: AppColors.warning,
                  icon: Icons.cloud_upload_outlined,
                ),
              ),
            const SizedBox(height: 14),
            _CustomerDetail(
              label: 'Total kunjungan',
              value: '${customer.visitCount}',
            ),
            const SizedBox(height: 12),
            _CustomerDetail(
              label: 'Total belanja',
              value: _currency.format(customer.totalSpent),
            ),
            if (customer.email != null) ...[
              const SizedBox(height: 12),
              _CustomerDetail(label: 'Email', value: customer.email!),
            ],
            if (customer.notes != null) ...[
              const SizedBox(height: 18),
              Text('Catatan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(customer.notes!),
            ],
            const SizedBox(height: 24),
            AppButton(
              text: 'Gunakan untuk pesanan',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: () {
                ref.read(cartProvider.notifier).setCustomer(customer.name);
                Navigator.pop(context);
                context.go('/pos');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.value,
    required this.onTap,
  });

  final CustomerModel customer;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = customer.name.trim().isEmpty
        ? 'P'
        : customer.name.trim()[0].toUpperCase();
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(initial, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (!customer.isSynced)
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 18,
                        color: AppColors.warning,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  customer.phone ?? customer.email ?? 'Tanpa kontak',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${customer.visitCount} kunjungan · $value',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _CustomerDetail extends StatelessWidget {
  const _CustomerDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm();

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
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
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nama',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Nama minimal 2 karakter'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nomor telepon',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) {
                final email = (value ?? '').trim();
                return email.isNotEmpty && !email.contains('@')
                    ? 'Masukkan email yang valid'
                    : null;
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
            const SizedBox(height: 20),
            AppButton(
              text: 'Simpan pelanggan',
              icon: Icons.check_rounded,
              onPressed: () {
                if (!(_formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  context,
                  CustomerDraft(
                    name: _name.text.trim(),
                    phone: _phone.text.trim(),
                    email: _email.text.trim(),
                    notes: _notes.text.trim(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
