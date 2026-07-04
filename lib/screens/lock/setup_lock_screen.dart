import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/lock_service.dart';

/// Set a PIN and enable app lock. Pops with `true` on success.
class SetupLockScreen extends StatefulWidget {
  const SetupLockScreen({super.key});

  @override
  State<SetupLockScreen> createState() => _SetupLockScreenState();
}

class _SetupLockScreenState extends State<SetupLockScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pin.text;
    if (pin.length < 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    if (pin != _confirm.text) {
      setState(() => _error = 'PINs don\'t match');
      return;
    }
    await LockService.setPin(pin);
    if (!mounted) return;
    await context.read<SettingsProvider>().setAppLock(true);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set app lock')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Choose a PIN to lock LunaTrack. If your device supports it, you '
            'can also unlock with biometrics.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'New PIN',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Enable app lock')),
        ],
      ),
    );
  }
}
