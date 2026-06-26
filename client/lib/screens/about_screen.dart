import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../l10n/strings.dart';

/// Source repository of this app.
const String _githubUrl = 'https://github.com/Vincenius/pckaiser-app';

/// The original "PCKaiser++" on the Good Old Days archive.
const String _originalGameUrl = 'https://www.goodolddays.net/en/game/PCKaiser/';

/// About: a short description of the game, the app version, and the
/// credits (original author + remake author).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('about'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.castle,
                  size: 36,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr('appTitle'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version $appVersion',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                tr('aboutDescription'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              Text(
                tr('creditsOriginal'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              // Link to the original game on the Good Old Days archive.
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(_originalGameUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('goodolddays.net'),
              ),
              const SizedBox(height: 8),
              Text(
                tr('creditsApp'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              // GitHub link (Material has no brand icons; the code symbol
              // with the "GitHub" label keeps it recognizable).
              FilledButton.tonalIcon(
                onPressed: () => launchUrl(
                  Uri.parse(_githubUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.code),
                label: const Text('GitHub — Quellcode'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
