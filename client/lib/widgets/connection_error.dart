import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/api_client.dart';

/// One shared presentation for a failed server call (user request
/// 2026-08-08): the classified message from [ApiError] plus, for a pure
/// transport failure, a "no connection" heading and a retry button —
/// before this, every online screen printed the raw one-liner
/// "Server nicht erreichbar: SocketException …" with no way to act on it.
class ConnectionErrorTile extends StatelessWidget {
  const ConnectionErrorTile({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  /// The failure to explain; a plain string keeps the old call sites
  /// working (they then read as a server rejection, not as offline).
  final ApiError error;

  /// Re-runs the failed call. Omitted where the screen refreshes itself.
  final Future<void> Function()? onRetry;

  /// Single-line variant for lists (no heading, no button).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offline = error.isOffline;
    final icon = offline ? Icons.cloud_off : Icons.error_outline;
    if (compact) {
      return ListTile(
        dense: true,
        leading: Icon(icon, color: theme.colorScheme.error),
        title: Text(error.message, style: theme.textTheme.bodySmall),
      );
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  // A rejection's heading stays neutral ("Meldung vom
                  // Server") — the old "Serverfehler (403)" read like a
                  // breakdown plus a mystery number, when the message
                  // below it already says what is wrong in plain words.
                  child: Text(
                    offline
                        ? tr('online.offlineBanner')
                        : tr('online.errServerTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              error.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onRetry!(),
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('online.retry')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
