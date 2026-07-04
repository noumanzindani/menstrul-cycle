import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/lock_service.dart';

/// Full-screen gate shown when the app is locked. Offers biometric unlock (auto
/// prompt) and PIN entry.
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 56, color: scheme.primary),
                const SizedBox(height: 16),
                Text('LunaTrack is locked',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Enter PIN',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Unlock'),
                ),
                if (_biometricAvailable) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use biometrics'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
