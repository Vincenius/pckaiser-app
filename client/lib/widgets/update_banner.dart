import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';

/// Play Store listing for the Android build. Opened from [UpdateRequiredBanner]
/// so a seat blocked by a newer match build can update in one tap. The id
/// matches the Android `applicationId` (`client/android/app/build.gradle.kts`).
const String playStoreUrl =
    'https://play.google.com/store/apps/details?id=com.pckaiser.app';

/// Shown on the online match screen when this build is older than the one the
/// match runs on (the server's `update_required` flag): the seat cannot take
/// its turn until the app is updated.
///
/// On Android it offers a one-tap link to the Play Store listing. iOS has no
/// published build yet, so the link is hidden there — the message alone tells
/// the player to update.
class UpdateRequiredBanner extends StatelessWidget {
  const UpdateRequiredBanner({super.key, this.serverVersion});

  /// The app version the match runs on (shown in the message); `'?'` when an
  /// older server doesn't report it.
  final String? serverVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onError = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.system_update, color: onError),
            title: Text(
              tr('setup.updateRequiredTitle'),
              style: TextStyle(color: onError),
            ),
            subtitle: Text(
              tr('setup.updateRequiredBody', {
                'version': serverVersion ?? '?',
              }),
              style: TextStyle(color: onError),
            ),
          ),
          // Android only for now — no iOS release to link to yet.
          if (defaultTargetPlatform == TargetPlatform.android)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(playStoreUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.shop),
                  label: Text(tr('setup.updatePlayStore')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
