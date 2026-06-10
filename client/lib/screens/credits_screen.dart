import 'package:flutter/material.dart';

import '../l10n/strings.dart';

/// Credits: the original game's author and the author of this remake.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('credits'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.castle,
                  size: 36, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 12),
            Text(tr('appTitle'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(letterSpacing: 2)),
            const SizedBox(height: 24),
            Text(tr('creditsOriginal'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(tr('creditsApp'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge),
          ]),
        ),
      ),
    );
  }
}
