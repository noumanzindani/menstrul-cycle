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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sent ? _sentState(theme, scheme) : _form(auth, theme),
            ),
          ),
        ),
      ),
      // Pinned rather than trailing the form, matching the app's other
      // single-action forms (`DayLogScreen`'s Save). Absent once the link is
      // on its way: there is nothing left to submit, and a live "Send reset
      // link" under a confirmation invites a second, identical email.
      bottomNavigationBar: _sent
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: FilledButton(
                key: const Key('forgot.submit'),
                onPressed: auth.busy ? null : _submit,
                child: const Text('Send reset link'),
              ),
            ),
    );
  }

  Widget _form(AuthProvider auth, ThemeData theme) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "We'll email you a link to set a new password.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const Key('forgot.email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your email' : null,
          ),
          if (auth.lastError != null) ...[
            const SizedBox(height: 12),
            Text(
              messageForAuthError(auth.lastError!),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  /// A calm confirmation card, not a toast: the next step happens in another
  /// app, so this has to stay on screen while the user goes to look for it.
  ///
  /// The copy stays deliberately generic about whether the address is
  /// registered — the same anti-enumeration reasoning as [_submit]. (The mock
  /// echoes the typed address back; that is harmless in itself but reads as a
  /// confirmation that the account exists, which is exactly the impression
  /// this screen must not give.)
  Widget _sentState(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Card(
          key: const Key('forgot.sent'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                Icon(Icons.mark_email_read_outlined,
                    size: 32, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'Check your email',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'If an account exists for that address, a reset link is on '
                  'its way. Check your inbox and spam folder.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('forgot.back'),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
