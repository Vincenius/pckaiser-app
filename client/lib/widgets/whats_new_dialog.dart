import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../release_notes.dart';

/// "What's new" modal shown once per app version (see `release_notes.dart`).
/// The caller decides *whether* to show it (SettingsService tracks the
/// last-seen version) and marks the version seen after it closes.
///
/// The bullets are rendered in a scrollable body so long notes never
/// overflow on a short screen or with large font scaling.
Future<void> showWhatsNewDialog(BuildContext context, ReleaseNote note) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.auto_awesome,
        color: theme.colorScheme.primary,
      ),
      title: Text(tr('whatsnew.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Version header, e.g. "Version 0.2.6".
            Text(
              tr('setup.version', {'version': note.version}),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in note.items())
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('whatsnew.close')),
        ),
      ],
    ),
  );
}
