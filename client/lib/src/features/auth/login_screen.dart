import 'package:flutter/material.dart';

import '../../app/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: 'owner@example.com');
  final _password = TextEditingController(text: 'change-me-now');
  final _totp = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _totp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.alternate_email_rounded,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 24),
                    Text('Self-hosted Mail',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('连接你的 VPS 邮箱后端',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _email,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person_outline),
                          labelText: '邮箱'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline),
                          labelText: '密码'),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _totp,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.pin_outlined),
                          labelText: 'TOTP，可选'),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: widget.state.isLoading ? null : _submit,
                      icon: widget.state.isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login_rounded),
                      label: const Text('登录'),
                    ),
                    if (widget.state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(widget.state.error!,
                          style: TextStyle(color: scheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    widget.state.login(_email.text.trim(), _password.text, _totp.text.trim());
  }
}
