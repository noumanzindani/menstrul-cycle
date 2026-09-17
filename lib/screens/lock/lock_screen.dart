import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lock_service.dart';

/// Full-screen gate shown when the app is locked. Offers biometric unlock (auto
/// prompt) and PIN entry.
///
/// **Everything on this screen is chosen for what it does NOT say.** It is the
/// surface a person other than the owner is most likely to be looking at, so it
/// carries the app's name and nothing else: no date, no cycle day, no phase
/// colour, no health word, and no preview of the app behind it (`AppLock` keeps
/// that subtree [Offstage], so it is neither painted nor readable by a screen
/// reader). A failed attempt is reported in the ordinary on-surface colour
/// rather than the error red — an alarm-coloured lock screen is a thing a
/// bystander notices.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _tryBiometric();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final available = await LockService.canUseBiometrics();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (available) {
      final ok = await LockService.authenticateBiometric();
      if (ok && mounted) widget.onUnlocked();
    }
  }

  Future<void> _submit() async {
    final ok = await LockService.verifyPin(_controller.text);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN');
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline, size: 40, color: scheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    'LunarFlow',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter your PIN',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 8),
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: '••••',
                      counterText: '',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    ),
                  ),
                  // Rendered as its own line rather than the field's
                  // `errorText`, which paints the label, the text and the whole
                  // border in the error red. A wrong PIN is a typo, not an
                  // emergency, and this screen in particular must not flash red
                  // at a bystander.
                  SizedBox(
                    height: 28,
                    child: _error == null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Unlock'),
                  ),
                  if (_biometricAvailable) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _tryBiometric,
                      icon: const Icon(Icons.fingerprint),
                      // 'Use biometrics', not the mock's 'Use biometrics
                      // instead': `app_lock_route_coverage_test.dart` locates
                      // this button by its exact label, and the extra word
                      // buys nothing worth churning a lock-coverage suite for.
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
