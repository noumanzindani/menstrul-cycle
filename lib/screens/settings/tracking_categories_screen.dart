import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/l10n.dart';
import '../../common/tracking_categories.dart';
import '../../providers/settings_provider.dart';

/// Lets the user choose which sections appear in the day editor. Hiding a
/// category is a display choice only — logged data is never deleted, which is
/// what the note below the title promises (and all it promises: prefixed groups
/// do not reach Insights or the doctor PDF, so claiming they would be visible
/// there would be false).
class TrackingCategoriesScreen extends StatelessWidget {
  const TrackingCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final enabled = settings.enabledCategories;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTrackingTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              context.l10n.settingsTrackingNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          for (final c in kTrackingCategories)
            SwitchListTile(
              title: Text(c.label),
              value: enabled.contains(c.id),
              onChanged: (v) => settings.setCategoryEnabled(c.id, v),
            ),
        ],
      ),
    );
  }
}
