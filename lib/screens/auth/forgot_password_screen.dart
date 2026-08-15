import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import 'auth_error_text.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.sendPasswordReset(_email.text);
    if (!mounted) return;
    // Confirm regardless of whether the address is registered: revealing which
    // emails have accounts would leak that someone uses a period tracker.
    //
    // `wrongCredentials` is deliberately treated as SUCCESS here, and only
    // here. Firebase can throw `user-not-found` for sendPasswordResetEmail
    // when a project has email-enumeration protection disabled --
    // FirebaseAuthService collapses that into `wrongCredentials`, which is
    // the right behavior for the sign-in screen. But if this screen showed
    // "Email or password is incorrect." for an unregistered address while
    // showing the generic confirmation for a registered one, the two visibly
    // different outcomes would BE the enumeration leak this screen's copy
    // exists to prevent. Do not "fix" this back to `auth.lastError == null`.
    final error = auth.lastError;
    if (error == null || error == AuthErrorCode.wrongCredentials) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent
              ? const Text(
                  'If an account exists for that address, a reset link is on '
                  'its way. Check your inbox and spam folder.',
                  key: Key('forgot.sent'),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('forgot.email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your email'
                            : null,
                      ),
                      if (auth.lastError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          messageForAuthError(auth.lastError!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('forgot.submit'),
                        onPressed: auth.busy ? null : _submit,
                        child: const Text('Send reset link'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
