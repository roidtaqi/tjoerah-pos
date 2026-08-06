import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/router/role_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_layout.dart';
import '../../../shared/components/app_badge.dart';
import '../../../shared/components/app_bottom_sheet.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../../../shared/components/app_empty_state.dart';
import '../../../shared/components/app_error_state.dart';
import '../../../shared/components/app_loading_state.dart';
import '../../../shared/components/app_search_bar.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/employee_models.dart';
import '../providers/employee_provider.dart';

class EmployeeManagementScreen extends ConsumerStatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  ConsumerState<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState
    extends ConsumerState<EmployeeManagementScreen> {
  String _query = '';
  String _status = 'active';
  String _role = 'all';
  bool _isMutating = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (!canManageAttendanceForUser(user)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Karyawan & akses')),
        body: const AppErrorState(
          title: 'Akses dibatasi',
          message: 'Hanya owner atau admin yang dapat mengelola karyawan.',
        ),
      );
    }

    final data = ref.watch(employeeProvider);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karyawan & akses'),
        actions: [
          if (wide)
            TextButton.icon(
              onPressed: _isMutating || data.value == null
                  ? null
                  : () => _openForm(data.requireValue),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Tambah karyawan'),
            )
          else
            IconButton(
              tooltip: 'Tambah karyawan',
              onPressed: _isMutating || data.value == null
                  ? null
                  : () => _openForm(data.requireValue),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isMutating
                ? null
                : () => ref.read(employeeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _isMutating
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton(
              tooltip: 'Tambah karyawan',
              onPressed: _isMutating || data.value == null
                  ? null
                  : () => _openForm(data.requireValue),
              child: const Icon(Icons.person_add_alt_1_outlined),
            ),
      body: data.when(
        loading: () =>
            const AppLoadingState(message: 'Memuat data karyawan...'),
        error: (_, _) => AppErrorState(
          title: 'Data karyawan belum tersedia',
          message: 'Pastikan server aktif dan akun memiliki akses.',
          onRetry: () => ref.read(employeeProvider.notifier).refresh(),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(EmployeeManagementState data) {
    final query = _query.trim().toLowerCase();
    final visible = data.employees.where((employee) {
      final matchesQuery =
          query.isEmpty ||
          employee.name.toLowerCase().contains(query) ||
          employee.employeeNumber.toLowerCase().contains(query) ||
          employee.email.toLowerCase().contains(query) ||
          (employee.username?.toLowerCase().contains(query) ?? false) ||
          (employee.phone?.toLowerCase().contains(query) ?? false);
      final matchesStatus =
          _status == 'all' ||
          (_status == 'active' && employee.isActive) ||
          (_status == 'inactive' && !employee.isActive);
      final matchesRole = _role == 'all' || employee.role == _role;
      return matchesQuery && matchesStatus && matchesRole;
    }).toList();

    return SafeArea(
      child: ListView(
        padding: AppSpacing.page(context),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal = constraints.maxWidth >= 720;
                      final search = AppSearchBar(
                        hintText: 'Cari nama, username, telepon, atau email',
                        onChanged: (value) => setState(() => _query = value),
                      );
                      final filters = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          DropdownMenu<String>(
                            width: 150,
                            initialSelection: _status,
                            label: const Text('Status'),
                            onSelected: (value) =>
                                setState(() => _status = value ?? 'all'),
                            dropdownMenuEntries: const [
                              DropdownMenuEntry(
                                value: 'active',
                                label: 'Aktif',
                              ),
                              DropdownMenuEntry(
                                value: 'inactive',
                                label: 'Nonaktif',
                              ),
                              DropdownMenuEntry(value: 'all', label: 'Semua'),
                            ],
                          ),
                          DropdownMenu<String>(
                            width: 190,
                            initialSelection: _role,
                            label: const Text('Role'),
                            onSelected: (value) =>
                                setState(() => _role = value ?? 'all'),
                            dropdownMenuEntries: [
                              const DropdownMenuEntry(
                                value: 'all',
                                label: 'Semua role',
                              ),
                              ...data.roles.map(
                                (role) => DropdownMenuEntry(
                                  value: role.value,
                                  label: role.label,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                      if (horizontal) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 12),
                            filters,
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [search, const SizedBox(height: 10), filters],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (visible.isEmpty)
                    AppEmptyState(
                      title: data.employees.isEmpty
                          ? 'Belum ada karyawan'
                          : 'Karyawan tidak ditemukan',
                      message: data.employees.isEmpty
                          ? 'Tambahkan karyawan beserta akun dan role kerjanya.'
                          : 'Coba pencarian atau filter yang berbeda.',
                      icon: Icons.badge_outlined,
                      onAction: data.employees.isEmpty && !_isMutating
                          ? () => _openForm(data)
                          : null,
                      actionLabel: data.employees.isEmpty
                          ? 'Tambah karyawan'
                          : null,
                    )
                  else
                    ...visible.map(
                      (employee) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EmployeeCard(
                          employee: employee,
                          roleLabel: _roleLabel(data, employee.role),
                          enabled: !_isMutating,
                          onEdit: () => _openForm(data, employee),
                          onDelete: () => _confirmDelete(employee),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(EmployeeManagementState data, String value) {
    return data.roles.where((role) => role.value == value).firstOrNull?.label ??
        value;
  }

  Future<void> _openForm(
    EmployeeManagementState data, [
    EmployeeProfile? employee,
  ]) async {
    final draft = await AppBottomSheet.show<EmployeeDraft>(
      context,
      title: employee == null ? 'Karyawan baru' : 'Edit karyawan',
      subtitle: employee == null
          ? 'Profil kerja dan akses aplikasi'
          : employee.name,
      child: _EmployeeForm(data: data, employee: employee),
    );
    if (draft == null || !mounted) return;
    setState(() => _isMutating = true);
    final result = employee == null
        ? await ref.read(employeeProvider.notifier).create(draft)
        : await ref
              .read(employeeProvider.notifier)
              .updateEmployee(employee, draft);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  Future<void> _confirmDelete(EmployeeProfile employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus karyawan?'),
        content: Text(
          '${employee.name} akan dihapus dan akun loginnya dinonaktifkan.',
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
    final result = await ref.read(employeeProvider.notifier).delete(employee);
    if (!mounted) return;
    setState(() => _isMutating = false);
    _showResult(result);
  }

  void _showResult(EmployeeMutationResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? null : AppColors.error,
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.roleLabel,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final EmployeeProfile employee;
  final String roleLabel;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final initial = employee.name.trim().isEmpty
        ? '?'
        : employee.name.trim()[0].toUpperCase();
    return AppCard(
      onTap: enabled ? onEdit : null,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              initial,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  employee.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${employee.employeeNumber} - ${employee.position ?? roleLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppBadge(text: roleLabel, icon: Icons.admin_panel_settings),
                    if (employee.outletName != null)
                      AppBadge(
                        text: employee.outletName!,
                        icon: Icons.store_outlined,
                      ),
                    AppBadge(
                      text: employee.isActive ? 'Aktif' : 'Nonaktif',
                      color: employee.isActive
                          ? AppColors.successSoft
                          : AppColors.surfaceMuted,
                      textColor: employee.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Aksi karyawan',
            enabled: enabled,
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
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
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({required this.data, this.employee});

  final EmployeeManagementState data;
  final EmployeeProfile? employee;

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  final _numberFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _outletFocus = FocusNode();
  final _roleFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late final TextEditingController _number;
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _position;
  late final TextEditingController _identityNumber;
  late final TextEditingController _address;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  late final TextEditingController _password;
  late final TextEditingController _pin;
  late String? _role;
  late int? _outletId;
  late String _employmentStatus;
  late String? _gender;
  late DateTime? _hireDate;
  late DateTime? _birthDate;
  late bool _isActive;
  bool _obscurePassword = true;
  bool _obscurePin = true;
  bool _showValidation = false;

  bool get _isNew => widget.employee == null;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _number = TextEditingController(text: employee?.employeeNumber);
    _name = TextEditingController(text: employee?.name);
    _username = TextEditingController(text: employee?.username);
    _email = TextEditingController(text: employee?.email);
    _phone = TextEditingController(text: employee?.phone);
    _position = TextEditingController(text: employee?.position);
    _identityNumber = TextEditingController(text: employee?.identityNumber);
    _address = TextEditingController(text: employee?.address);
    _emergencyName = TextEditingController(
      text: employee?.emergencyContactName,
    );
    _emergencyPhone = TextEditingController(
      text: employee?.emergencyContactPhone,
    );
    _password = TextEditingController();
    _pin = TextEditingController();
    for (final controller in [
      _number,
      _name,
      _username,
      _email,
      _phone,
      _pin,
      _password,
    ]) {
      controller.addListener(_refreshValidationSummary);
    }
    _role =
        employee?.role ??
        widget.data.roles.where((role) => role.assignable).firstOrNull?.value;
    _outletId = employee?.outletId ?? widget.data.outlets.firstOrNull?.id;
    _employmentStatus =
        employee?.employmentStatus ??
        widget.data.employmentStatuses.firstOrNull?.value ??
        'permanent';
    _gender = employee?.gender;
    _hireDate = employee?.hireDate ?? DateTime.now();
    _birthDate = employee?.birthDate;
    _isActive = employee?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _number,
      _name,
      _username,
      _email,
      _phone,
      _position,
      _identityNumber,
      _address,
      _emergencyName,
      _emergencyPhone,
      _password,
      _pin,
    ]) {
      controller.dispose();
    }
    for (final focusNode in [
      _numberFocus,
      _nameFocus,
      _outletFocus,
      _roleFocus,
      _usernameFocus,
      _emailFocus,
      _phoneFocus,
      _pinFocus,
      _passwordFocus,
    ]) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: _showValidation
          ? AutovalidateMode.always
          : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const _FormSection(title: 'Data kerja'),
          const SizedBox(height: 4),
          Text(
            'Kolom bertanda * wajib diisi',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _number,
            focusNode: _numberFocus,
            decoration: const InputDecoration(
              labelText: 'Nomor karyawan *',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: _required,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            focusNode: _nameFocus,
            decoration: const InputDecoration(
              labelText: 'Nama lengkap *',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
            validator: _required,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            focusNode: _outletFocus,
            isExpanded: true,
            initialValue: _outletId,
            decoration: const InputDecoration(
              labelText: 'Outlet *',
              prefixIcon: Icon(Icons.store_outlined),
            ),
            items: widget.data.outlets
                .map(
                  (outlet) => DropdownMenuItem(
                    value: outlet.id,
                    child: Text(outlet.name),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _outletId = value),
            validator: (value) => value == null ? 'Pilih outlet.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _position,
            decoration: const InputDecoration(
              labelText: 'Jabatan (opsional)',
              prefixIcon: Icon(Icons.work_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _employmentStatus,
            decoration: const InputDecoration(
              labelText: 'Status kerja *',
              prefixIcon: Icon(Icons.assignment_ind_outlined),
            ),
            items: widget.data.employmentStatuses
                .map(
                  (status) => DropdownMenuItem(
                    value: status.value,
                    child: Text(status.label),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _employmentStatus = value ?? 'permanent'),
            validator: (value) => value == null ? 'Pilih status kerja.' : null,
          ),
          const SizedBox(height: 12),
          _DateField(
            label: 'Tanggal mulai kerja (opsional)',
            value: _hireDate,
            onChanged: (value) => setState(() => _hireDate = value),
          ),
          const SizedBox(height: 20),
          const _FormSection(title: 'Akses aplikasi'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            focusNode: _roleFocus,
            isExpanded: true,
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role utama *',
              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
            ),
            items: widget.data.roles
                .map(
                  (role) => DropdownMenuItem(
                    value: role.value,
                    enabled: role.assignable || role.value == _role,
                    child: Text(role.label),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _role = value),
            validator: (value) => value == null ? 'Pilih role.' : null,
          ),
          if (_role != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.data.roles
                      .where((role) => role.value == _role)
                      .firstOrNull
                      ?.description ??
                  '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _username,
            focusNode: _usernameFocus,
            decoration: const InputDecoration(
              labelText: 'Username login (opsional)',
              hintText: 'Contoh: ayu.lestari',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
            ],
            validator: (value) {
              final username = value?.trim() ?? '';
              if (username.isEmpty) return null;
              if (username.length < 3) return 'Username minimal 3 karakter.';
              return RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]*$').hasMatch(username)
                  ? null
                  : 'Awali dengan huruf; gunakan angka, titik, garis bawah, atau strip setelahnya.';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            focusNode: _emailFocus,
            decoration: const InputDecoration(
              labelText: 'Email login *',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              final error = _required(value);
              if (error != null) return error;
              return value!.contains('@') ? null : 'Email tidak valid.';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            focusNode: _phoneFocus,
            decoration: const InputDecoration(
              labelText: 'Nomor telepon login (opsional)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.isNotEmpty &&
                      (digits.length < 8 || digits.length > 15)
                  ? 'Nomor telepon harus terdiri dari 8-15 angka.'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pin,
            focusNode: _pinFocus,
            decoration: InputDecoration(
              labelText: _isNew ? 'PIN login *' : 'PIN baru (opsional)',
              prefixIcon: const Icon(Icons.pin_outlined),
              suffixIcon: IconButton(
                tooltip: _obscurePin ? 'Tampilkan PIN' : 'Sembunyikan PIN',
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
                icon: Icon(
                  _obscurePin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            maxLength: 6,
            validator: (value) {
              final pin = value?.trim() ?? '';
              if (_isNew && pin.isEmpty) return 'PIN wajib diisi.';
              if (pin.isNotEmpty && !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                return 'PIN harus terdiri dari 4-6 angka.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            focusNode: _passwordFocus,
            decoration: InputDecoration(
              labelText: _isNew ? 'Password *' : 'Password baru (opsional)',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? 'Tampilkan password'
                    : 'Sembunyikan password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            obscureText: _obscurePassword,
            validator: (value) {
              final password = value ?? '';
              if (_isNew && password.isEmpty) {
                return 'Password wajib diisi.';
              }
              if (password.isNotEmpty && password.length < 8) {
                return 'Password minimal 8 karakter.';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          const _FormSection(title: 'Data pribadi'),
          const SizedBox(height: 10),
          _DateField(
            label: 'Tanggal lahir (opsional)',
            value: _birthDate,
            lastDate: DateTime.now().subtract(const Duration(days: 1)),
            onChanged: (value) => setState(() => _birthDate = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _gender,
            decoration: const InputDecoration(
              labelText: 'Jenis kelamin (opsional)',
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
            items: const [
              DropdownMenuItem<String?>(
                value: null,
                child: Text('Tidak diisi'),
              ),
              DropdownMenuItem(value: 'male', child: Text('Laki-laki')),
              DropdownMenuItem(value: 'female', child: Text('Perempuan')),
              DropdownMenuItem(value: 'other', child: Text('Lainnya')),
            ],
            onChanged: (value) => setState(() => _gender = value),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _identityNumber,
            decoration: const InputDecoration(
              labelText: 'Nomor identitas (opsional)',
              prefixIcon: Icon(Icons.credit_card_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Alamat (opsional)',
              prefixIcon: Icon(Icons.home_outlined),
              alignLabelWithHint: true,
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 20),
          const _FormSection(title: 'Kontak darurat'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _emergencyName,
            decoration: const InputDecoration(
              labelText: 'Nama kontak (opsional)',
              prefixIcon: Icon(Icons.contact_emergency_outlined),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emergencyPhone,
            decoration: const InputDecoration(
              labelText: 'Nomor kontak (opsional)',
              prefixIcon: Icon(Icons.phone_callback_outlined),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Akun aktif'),
            subtitle: const Text('Akun nonaktif tidak dapat login'),
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
          ),
          const SizedBox(height: 16),
          if (_showValidation && _validationIssues.isNotEmpty) ...[
            _ValidationSummary(issues: _validationIssues),
            const SizedBox(height: 12),
          ],
          AppButton(
            text: _isNew ? 'Tambahkan karyawan' : 'Simpan perubahan',
            icon: _isNew
                ? Icons.person_add_alt_1_outlined
                : Icons.save_outlined,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _showValidation = true);
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _role == null || _outletId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusFirstInvalid());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi kolom wajib yang ditandai *.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      EmployeeDraft(
        employeeNumber: _number.text.trim(),
        name: _name.text.trim(),
        email: _email.text.trim(),
        username: _nullable(_username.text),
        role: _role!,
        outletId: _outletId!,
        attendanceShiftId: null,
        phone: _nullable(_phone.text),
        position: _nullable(_position.text),
        employmentStatus: _employmentStatus,
        hireDate: _hireDate,
        birthDate: _birthDate,
        gender: _gender,
        identityNumber: _nullable(_identityNumber.text),
        address: _nullable(_address.text),
        emergencyContactName: _nullable(_emergencyName.text),
        emergencyContactPhone: _nullable(_emergencyPhone.text),
        password: _nullable(_password.text),
        pin: _nullable(_pin.text),
        isActive: _isActive,
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? 'Kolom ini wajib diisi.'
        : null;
  }

  List<String> get _validationIssues {
    final issues = <String>[];
    if (_number.text.trim().isEmpty) issues.add('Nomor karyawan');
    if (_name.text.trim().isEmpty) issues.add('Nama lengkap');
    if (_outletId == null) issues.add('Outlet');
    if (_employmentStatus.trim().isEmpty) issues.add('Status kerja');
    if (_role == null) issues.add('Role');
    final username = _username.text.trim();
    if (username.isNotEmpty && username.length < 3) {
      issues.add('Username minimal 3 karakter');
    } else if (username.isNotEmpty &&
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9._-]*$').hasMatch(username)) {
      issues.add('Format username login');
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      issues.add('Email login');
    } else if (!email.contains('@')) {
      issues.add('Format email login');
    }
    final phoneDigits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isNotEmpty &&
        (phoneDigits.length < 8 || phoneDigits.length > 15)) {
      issues.add('Nomor telepon 8-15 angka');
    }
    final pin = _pin.text.trim();
    if (_isNew && pin.isEmpty) {
      issues.add('PIN login');
    } else if (pin.isNotEmpty && !RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      issues.add('PIN 4-6 angka');
    }
    final password = _password.text;
    if (_isNew && password.isEmpty) {
      issues.add('Password');
    } else if (password.isNotEmpty && password.length < 8) {
      issues.add('Password minimal 8 karakter');
    }
    return issues;
  }

  void _focusFirstInvalid() {
    if (!mounted) return;
    if (_number.text.trim().isEmpty) {
      _numberFocus.requestFocus();
    } else if (_name.text.trim().isEmpty) {
      _nameFocus.requestFocus();
    } else if (_outletId == null) {
      _outletFocus.requestFocus();
    } else if (_role == null) {
      _roleFocus.requestFocus();
    } else if ((_username.text.trim().isNotEmpty &&
            _username.text.trim().length < 3) ||
        (_username.text.trim().isNotEmpty &&
            !RegExp(
              r'^[a-zA-Z][a-zA-Z0-9._-]*$',
            ).hasMatch(_username.text.trim()))) {
      _usernameFocus.requestFocus();
    } else if (_email.text.trim().isEmpty ||
        !_email.text.trim().contains('@')) {
      _emailFocus.requestFocus();
    } else if (_phone.text.replaceAll(RegExp(r'\D'), '').isNotEmpty &&
        (_phone.text.replaceAll(RegExp(r'\D'), '').length < 8 ||
            _phone.text.replaceAll(RegExp(r'\D'), '').length > 15)) {
      _phoneFocus.requestFocus();
    } else if ((_isNew && _pin.text.trim().isEmpty) ||
        (_pin.text.trim().isNotEmpty &&
            !RegExp(r'^\d{4,6}$').hasMatch(_pin.text.trim()))) {
      _pinFocus.requestFocus();
    } else if ((_isNew && _password.text.isEmpty) ||
        (_password.text.isNotEmpty && _password.text.length < 8)) {
      _passwordFocus.requestFocus();
    }
  }

  void _refreshValidationSummary() {
    if (_showValidation && mounted) setState(() {});
  }

  String? _nullable(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lengkapi data wajib',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 3),
                Text(
                  issues.join(', '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final now = DateTime.now();
        final maximum = lastDate ?? DateTime(now.year + 2);
        final selected = await showDatePicker(
          context: context,
          firstDate: DateTime(1940),
          lastDate: maximum,
          initialDate: value ?? (now.isAfter(maximum) ? maximum : now),
        );
        if (selected != null) onChanged(selected);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: value == null
              ? null
              : IconButton(
                  tooltip: 'Hapus tanggal',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          value == null
              ? 'Belum diisi'
              : DateFormat('dd MMM yyyy').format(value!),
        ),
      ),
    );
  }
}
