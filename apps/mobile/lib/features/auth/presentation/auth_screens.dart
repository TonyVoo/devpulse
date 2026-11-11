import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/tokens.dart';
import '../../../core/design_system/widgets/dp_widgets.dart';
import '../../../core/result/failure.dart';
import '../domain/models.dart';
import 'session_controller.dart';

enum AuthMode { login, register }

/// Human field messages for the API's validation errors.
String? fieldMessage(String field, Map<String, String> fields) {
  final raw = fields[field];
  if (raw == null) return null;
  if (field == 'password' && raw.contains('at least')) return 'Use at least 12 characters.';
  if (field == 'email') return 'Enter a valid email address.';
  return raw;
}

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({required this.mode, this.from, super.key});

  final AuthMode mode;
  final String? from;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _pending = false;
  Failure? _failure;

  bool get _isLogin => widget.mode == AuthMode.login;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _failure = null;
    });
    final session = ref.read(sessionControllerProvider.notifier);
    try {
      if (_isLogin) {
        await session.login(_email.text, _password.text);
      } else {
        await session.register(_name.text, _email.text, _password.text);
      }
      TextInput.finishAutofillContext();
      // The router redirects on the new session state.
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _failure = f);
      unawaited(HapticFeedback.mediumImpact()); // feedback must never block the UI
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final session = ref.watch(sessionControllerProvider).value;
    final reason = session is SignedOut ? session.reason : null;
    final fields = _failure is ValidationFailure ? (_failure! as ValidationFailure).fields : const <String, String>{};
    final formMessage = switch (_failure) {
      null => null,
      ValidationFailure() => 'Check the highlighted fields.',
      final f => f.message,
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DpSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: DpLogo(size: 17)),
                    const SizedBox(height: DpSpace.xxl),
                    Text(_isLogin ? 'Sign in' : 'Create your account', style: t.headlineSmall),
                    const SizedBox(height: DpSpace.lg),
                    if (formMessage != null || (reason != null && _isLogin)) ...[
                      DpBanner(
                        message: formMessage ?? reason!,
                        tone: formMessage != null ? DpBannerTone.error : DpBannerTone.info,
                      ),
                      const SizedBox(height: DpSpace.lg),
                    ],
                    if (!_isLogin) ...[
                      DpTextField(
                        label: 'Name',
                        controller: _name,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        errorText: fieldMessage('display_name', fields),
                        enabled: !_pending,
                      ),
                      const SizedBox(height: DpSpace.md),
                    ],
                    DpTextField(
                      label: 'Work email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      errorText: fieldMessage('email', fields),
                      enabled: !_pending,
                    ),
                    const SizedBox(height: DpSpace.md),
                    DpTextField(
                      label: 'Password',
                      controller: _password,
                      obscure: true,
                      autofillHints: [_isLogin ? AutofillHints.password : AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      helperText: _isLogin ? null : 'At least 12 characters.',
                      errorText: fieldMessage('password', fields),
                      enabled: !_pending,
                    ),
                    const SizedBox(height: DpSpace.xl),
                    DpButton(
                      label: _isLogin ? 'Sign in' : 'Create account',
                      onPressed: _submit,
                      loading: _pending,
                      expand: true,
                    ),
                    const SizedBox(height: DpSpace.md),
                    TextButton(
                      onPressed: _pending ? null : () => context.go(_isLogin ? '/register' : '/login'),
                      child: Text(_isLogin ? 'New to DevPulse? Create an account' : 'Already have an account? Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
