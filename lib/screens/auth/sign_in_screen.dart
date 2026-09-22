import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/cloud_sync_unavailable_banner.dart';
import 'auth_error_text.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';

/// The app's mark: a ring of short arc segments, echoing the month ring on
/// Today without pretending to be it.
///
/// Decorative only — nothing here is derived from cycle data, and the two
/// surfaces that show it (the gate's splash and the sign-in wall) both render
/// before any of that data is loaded. The segments are drawn as explicit arcs
/// with BUTT caps rather than a dashed stroke: a round cap adds half the stroke
/// width to each end of every segment, which at this size fuses them into a
/// solid ring (the same trap `docs/design/stitch/README.md` records for the
/// real month ring).
class LunaRingMark extends StatelessWidget {
  const LunaRingMark({super.key, this.size = 44, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingMarkPainter(
          color ?? Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _RingMarkPainter extends CustomPainter {
  const _RingMarkPainter(this.color);

  final Color color;

  static const int _segments = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.1;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke;
    const sweep = 2 * math.pi / _segments;
    const gap = sweep * 0.34;
    for (var i = 0; i < _segments; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.showContinueWithoutSync = false,
    this.onContinueWithoutSync,
  });

  /// Whether to offer the "Continue without syncing" hatch below the form.
  ///
  /// Set by `AppGate`, and ONLY by it, from `FirebaseAvailability` — never
  /// from an [AuthErrorCode] (a wrong password is indistinguishable from a
  /// genuine outage by error code alone, and gating on it would hand a
  /// local-only bypass to anyone who mistypes a password). See `AppGate`'s
  /// `_localOnly` doc comment for the full ruling this implements.
  final bool showContinueWithoutSync;

  /// Enters local-only mode. Null (and the hatch not rendered at all) unless
  /// [showContinueWithoutSync] is true — see `AppGate.build`.
  final VoidCallback? onContinueWithoutSync;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AuthProvider>().signIn(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: AppLogo()),
                    const SizedBox(height: 16),
                    Text(
                      'LunarFlow',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Deliberately NOT the mock's "Your cycle, kept private."
                    // Daily logs sync to the server in plain text and the
                    // operator can read them (see `PRIVACY_POLICY.md`), so a
                    // bare privacy promise on the wall in front of the app is
                    // the kind of copy CLAUDE.md's honesty guardrail exists to
                    // stop. This says what signing in is FOR instead.
                    Text(
                      'Sign in to sync your logs to your other devices.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    // Only reachable when `AppGate` was told this build has no
                    // usable Firebase app at all — see [showContinueWithoutSync].
                    // Placed above the form, NOT at the bottom where the mock
                    // puts it: signing in can never succeed on a device in this
                    // state, so the only way past a dead form comes first
                    // rather than below it.
                    if (widget.showContinueWithoutSync) ...[
                      const SizedBox(height: 24),
                      const CloudSyncUnavailableBanner(),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const Key('signIn.continueWithoutSync'),
                        // The app theme styles filled buttons only; this
                        // matches their 52dp height and 16dp radius by hand so
                        // the hatch is a peer of the dead "Sign in" below it.
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: widget.onContinueWithoutSync,
                        child: const Text('Continue without syncing'),
                      ),
                      const SizedBox(height: 28),
                      Divider(color: scheme.outlineVariant, height: 1),
                    ],
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('signIn.email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Enter your email'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('signIn.password'),
                      controller: _password,
                      obscureText: !_showPassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Enter your password'
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
                      key: const Key('signIn.submit'),
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('signIn.toSignUp'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SignUpScreen(),
                        ),
                      ),
                      child: const Text('Create an account'),
                    ),
                    TextButton(
                      key: const Key('signIn.forgot'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordScreen(),
                        ),
                      ),
                      child: const Text('Forgot password?'),
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
