import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
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
  bool _showPassword = false;

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      // Bare back arrow: the heading below carries the title, so an app-bar
      // copy of it would be the same words twice on a 360dp-wide screen.
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 72)),
                  const SizedBox(height: 16),
                  Text(
                    'Create your account',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('signUp.email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty) return 'Enter your email';
                      if (!value.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('signUp.password'),
                    controller: _password,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 8 characters',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(_showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        tooltip:
                            _showPassword ? 'Hide password' : 'Show password',
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Use at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('signUp.confirm'),
                    controller: _confirm,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v != _password.text)
                        ? 'Passwords do not match'
                        : null,
                  ),
                  if (auth.lastError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      messageForAuthError(auth.lastError!),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('signUp.submit'),
                    onPressed: auth.busy ? null : _submit,
                    child: const Text('Create account'),
                  ),
                  const SizedBox(height: 24),
                  // The plaintext-sync disclosure, in the same rounded-strip
                  // language as `DisclaimerBanner` and
                  // `CloudSyncUnavailableBanner` rather than a fourth visual
                  // idiom for fine print.
                  //
                  // It is on THIS screen because this is the moment the
                  // decision is made, and every clause of it is a fact about
                  // what the code does today: `SyncService` mirrors daily logs
                  // and preference settings to `users/{uid}` unencrypted, and
                  // uploaded media bytes sit unencrypted in Cloud Storage. Do
                  // not soften it to "securely stored" — see `PRIVACY_POLICY.md`
                  // and CLAUDE.md's copy guardrail.
                  Container(
                    key: const Key('signUp.syncDisclosure'),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_outlined,
                            size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your daily logs and settings sync to our server '
                            'so they reach your other devices. They are '
                            'encrypted in transit and stored in plain text — '
                            'which means we can read them. Photos you add are '
                            'stored unencrypted.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
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
