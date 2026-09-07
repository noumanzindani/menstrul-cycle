import 'package:flutter/material.dart';

import '../../common/l10n.dart';

/// The three primitives the redesigned settings list is built from.
///
/// See `docs/design/stitch/06-settings.html`: a small accent-coloured header,
/// then its rows inside one rounded surface, separated by hairlines inset past
/// the icon column. Whitespace — not a full-width `Divider` — separates groups.
///
/// The header is rendered in the string's OWN case, deliberately not
/// `toUpperCase()`d the way the mock draws it. Widget tests match on the
/// rendered string (`settings_backup_test.dart` asserts
/// `find.text('Backup & restore')`, which is this header), and nothing else in
/// `lib/` upper-cases a heading — `day_entry_form.dart`'s `_SectionLabel`
/// carries the same note for the same reason.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  /// Group heading, e.g. "Backup & restore".
  final String title;

  /// The rows. Usually `ListTile` / `SwitchListTile`; `if (…)` entries are
  /// fine — an empty list renders the header alone, so callers that can filter
  /// every row away should not build the group at all.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          // A Material (not a DecoratedBox) so the rows' ink splashes are
          // clipped to the group's corners instead of painting square over
          // them on the Scaffold's own Material.
          Material(
            color: scheme.surfaceContainerLow,
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _hairlined(scheme),
            ),
          ),
        ],
      ),
    );
  }

  /// Interleaves hairlines between rows, inset past the leading icon column so
  /// the rule starts at the text rather than cutting the whole row in half.
  List<Widget> _hairlined(ColorScheme scheme) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(Divider(
          height: 1,
          thickness: 1,
          indent: 56,
          endIndent: 0,
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ));
      }
      out.add(children[i]);
    }
    return out;
  }
}

/// The right-hand value on a row that opens a picker ("System", "28 days").
///
/// The presence of this instead of a chevron is the whole navigational grammar
/// of the screen: a value means "this row chooses something", a chevron means
/// "this row goes somewhere".
class SettingsValue extends StatelessWidget {
  const SettingsValue(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      value,
      textAlign: TextAlign.end,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The closing paragraph under the list.
///
/// [text] is nullable and defaults to `l10n.settingsAboutBody` — the legally
/// load-bearing one: encrypted on device, the synced copy is NOT end-to-end
/// encrypted, predictions are estimates and not a contraceptive method. Do not
/// pass a shorter string in its place on the settings screen.
class SettingsFinePrint extends StatelessWidget {
  const SettingsFinePrint(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text ?? context.l10n.settingsAboutBody,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}
