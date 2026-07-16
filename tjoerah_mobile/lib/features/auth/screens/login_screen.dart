import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/router/role_navigation.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_card.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  bool _usePin = false;
  bool _hidePassword = true;
  bool _loading = false;
  bool _checkingSession = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    await ref.read(authProvider.notifier).checkAuthStatus();
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      context.go(homePathForUser(auth.user));
      return;
    }
    setState(() => _checkingSession = false);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final result = await ref
        .read(authProvider.notifier)
        .login(
          _usePin ? _pinController.text : _emailController.text.trim(),
          _usePin ? '' : _passwordController.text,
          isPin: _usePin,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.isSuccess) {
      context.go(homePathForUser(ref.read(authProvider).user));
    } else {
      setState(() {
        _errorMessage = _loginErrorMessage(result.failure!, isPin: _usePin);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'T',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Tjoerah POS',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Masuk untuk melanjutkan pekerjaan',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    child: _checkingSession
                        ? const SizedBox(
                            height: 280,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 14),
                                  Text('Memeriksa sesi...'),
                                ],
                              ),
                            ),
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SegmentedButton<bool>(
                                  expandedInsets: EdgeInsets.zero,
                                  segments: const [
                                    ButtonSegment(
                                      value: false,
                                      icon: Icon(Icons.mail_outline_rounded),
                                      label: Text('Email'),
                                    ),
                                    ButtonSegment(
                                      value: true,
                                      icon: Icon(Icons.dialpad_rounded),
                                      label: Text('PIN'),
                                    ),
                                  ],
                                  selected: {_usePin},
                                  showSelectedIcon: false,
                                  onSelectionChanged: (selection) {
                                    setState(() {
                                      _usePin = selection.first;
                                      _errorMessage = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 20),
                                if (_usePin)
                                  TextFormField(
                                    key: const ValueKey('pin-field'),
                                    controller: _pinController,
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    obscureText: true,
                                    obscuringCharacter: '*',
                                    maxLength: 6,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'PIN',
                                      hintText: '4-6 digit',
                                      counterText: '',
                                      prefixIcon: Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                    ),
                                    validator: (value) {
                                      final length = value?.length ?? 0;
                                      return length < 4
                                          ? 'PIN minimal 4 digit'
                                          : null;
                                    },
                                    onFieldSubmitted: (_) => _submit(),
                                  )
                                else ...[
                                  TextFormField(
                                    key: const ValueKey('email-field'),
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.email],
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      hintText: 'nama@perusahaan.com',
                                      prefixIcon: Icon(
                                        Icons.mail_outline_rounded,
                                      ),
                                    ),
                                    validator: (value) {
                                      final email = (value ?? '').trim();
                                      return !email.contains('@')
                                          ? 'Masukkan email yang valid'
                                          : null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _hidePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Kata sandi akun',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: _hidePassword
                                            ? 'Tampilkan kata sandi'
                                            : 'Sembunyikan kata sandi',
                                        onPressed: () {
                                          setState(
                                            () =>
                                                _hidePassword = !_hidePassword,
                                          );
                                        },
                                        icon: Icon(
                                          _hidePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (value) => (value ?? '').isEmpty
                                        ? 'Kata sandi wajib diisi'
                                        : null,
                                    onFieldSubmitted: (_) => _submit(),
                                  ),
                                ],
                                if (_errorMessage != null) ...[
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.error_outline_rounded,
                                          size: 20,
                                          color: theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onErrorContainer,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                AppButton(
                                  text: _usePin
                                      ? 'Masuk dengan PIN'
                                      : 'Masuk ke Tjoerah POS',
                                  icon: Icons.arrow_forward_rounded,
                                  isLoading: _loading,
                                  onPressed: _submit,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Transaksi offline tetap tersimpan aman di perangkat',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _loginErrorMessage(AuthLoginFailure failure, {required bool isPin}) {
  return switch (failure) {
    AuthLoginFailure.invalidCredentials =>
      isPin
          ? 'PIN tidak dikenali. Periksa kembali atau gunakan email.'
          : 'Email atau kata sandi tidak sesuai.',
    AuthLoginFailure.connection =>
      'Tidak dapat terhubung ke server. Periksa koneksi lalu coba lagi.',
    AuthLoginFailure.serviceUnavailable =>
      'Layanan sedang bermasalah. Tunggu sebentar lalu coba lagi.',
    AuthLoginFailure.unexpectedResponse =>
      'Respons server tidak dapat diproses. Coba lagi.',
  };
}
