import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../models/enums.dart';
import '../../providers/log_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/lock_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/ad_banner.dart';
import '../lock/setup_lock_screen.dart';
import '../premium/premium_screen.dart';
import '../reminders/reminders_screen.dart';

/// App settings: appearance, cycle defaults (feed prediction when history is
/// thin), reminders, and the required disclaimer/about.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This permanently erases every period, symptom, reminder, and '
          'setting on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Capture everything that needs `context` BEFORE the async gaps.
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    final messenger = ScaffoldMessenger.of(context);

    await db.deleteAllData();
    await LockService.clearPin();
    await NotificationService.cancel(NotificationService.idLogNudge);
    await NotificationService.cancel(NotificationService.idPeriodSoon);
    await NotificationService.cancel(NotificationService.idFertile);
    await settings.load();
    await logs.load();
    messenger.showSnackBar(
      const SnackBar(content: Text('All data deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final premium = context.watch<PremiumProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      bottomNavigationBar: const SafeArea(child: AdBanner()),
      body: ListView(
        children: [
          const _SectionHeader('Premium'),
          ListTile(
            leading: Icon(
              premium.isPremium
                  ? Icons.workspace_premium
                  : Icons.workspace_premium_outlined,
            ),
            title: Text(premium.isPremium ? 'Premium active' : 'Go Premium'),
            subtitle: Text(premium.isPremium
                ? 'Ads removed — thank you!'
                : 'Remove ads and unlock extras'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PremiumScreen()),
            ),
          ),
          const Divider(),
          const _SectionHeader('Appearance'),
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (m) {
              if (m != null) settings.setThemeMode(m);
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: ThemeMode.system,
                  title: Text('System default'),
                ),
                RadioListTile(value: ThemeMode.light, title: Text('Light')),
                RadioListTile(value: ThemeMode.dark, title: Text('Dark')),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Goal'),
          RadioGroup<TrackingMode>(
            groupValue: settings.mode,
            onChanged: (m) {
              if (m != null) settings.setMode(m);
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: TrackingMode.track,
                  title: Text('Track my cycle'),
                  subtitle: Text('Lead with your next period and phase'),
                ),
                RadioListTile(
                  value: TrackingMode.conceive,
                  title: Text('Try to conceive'),
                  subtitle: Text('Lead with fertile days and ovulation'),
                ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Cycle defaults'),
          _StepperTile(
            title: 'Average cycle length',
            suffix: 'days',
            value: settings.cycleLength,
            min: 21,
            max: 35,
            onChanged: settings.setCycleLength,
          ),
          _StepperTile(
            title: 'Average period length',
            suffix: 'days',
            value: settings.periodLength,
            min: 2,
            max: 10,
            onChanged: settings.setPeriodLength,
          ),
          const Divider(),
          const _SectionHeader('Reminders'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Reminders'),
            subtitle: const Text('Period, fertile window, and daily log'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RemindersScreen()),
            ),
          ),
          const Divider(),
          const _SectionHeader('Language'),
          SwitchListTile(
            secondary: const Icon(Icons.diversity_3_outlined),
            title: const Text('Gender-neutral language'),
            subtitle: const Text('Use inclusive wording throughout the app'),
            value: settings.genderNeutralLanguage,
            onChanged: settings.setGenderNeutralLanguage,
          ),
          const Divider(),
          const _SectionHeader('Privacy'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text('Require a PIN or biometrics to open'),
            value: settings.appLockEnabled,
            onChanged: (v) async {
              if (v) {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const SetupLockScreen()),
                );
              } else {
                await LockService.clearPin();
                await settings.setAppLock(false);
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error),
            title: const Text('Delete all my data'),
            subtitle: const Text('Permanently erase everything on this device'),
            onTap: () => _confirmDeleteAll(context),
          ),
          const Divider(),
          const _SectionHeader('About'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Text(
              'LunaTrack stores all your data privately on this device. '
              'Predictions are estimates and are not a contraceptive method or '
              'a substitute for medical advice.',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.title,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String suffix;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Text('$value $suffix'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
