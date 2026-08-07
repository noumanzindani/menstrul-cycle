import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_error_text.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Signs up and, on success, POPS.
  ///
  /// The pop is load-bearing and not cosmetic. This screen is pushed as a route
  /// by `SignInScreen`, whereas `AppGate` *returns* `SignInScreen` from its
  /// `build`. So a successful sign-up does swap what `home:` holds over to
  /// `AppShell` — underneath a route that nothing else will ever remove. The
  /// user was left on this form, with the button re-enabled by `AuthProvider`'s
  /// `finally`, every honest signal saying the tap failed; tapping again then
  /// answered "An account already exists for that email", which is the exact
  /// opposite of what happened. Only the system back button escaped, and it
  /// reads like abandoning the sign-up.
  ///
  /// Gated on [AuthProvider.lastError], NOT on the future completing:
  /// `AuthProvider._guard` catches `AuthFailure` and records the code rather
  /// than rethrowing, so `await` returns normally on failure too. An
  /// unconditional pop would throw the error message away before it is read.
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Read before the await: `context` must not be used across an async gap.
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    await auth.signUp(email: _email.text, password: _password.text);
    if (!mounted || auth.lastError != null) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('signUp.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter your email';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signUp.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Use at least 8 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signUp.confirm'),
                  controller: _confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) => (v != _password.text)
                      ? 'Passwords do not match'
                      : null,
                ),
                if (auth.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    messageForAuthError(auth.lastError!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('signUp.submit'),
                  onPressed: auth.busy ? null : _submit,
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
