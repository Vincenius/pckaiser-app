import 'package:flutter/material.dart';

import '../l10n/strings.dart' show tr;

/// The server-hosted matchmaking rooms ("offizielle Partien"): permanently
/// open matches anyone can drop into without a room code. The server sends
/// only the stable template key (`settings.template`) — every display name
/// is localized here, never sent over the wire (CLAUDE.md, bilingual UI).
///
/// They must read as a different KIND of entry than a player-hosted game,
/// hence the accent-framed card below instead of the plain list tile.

/// Localized room name, or null for an ordinary player-hosted match (also
/// covers a template a future server knows and this build does not).
String? roomTitle(String? template) => switch (template) {
  'blitz' => tr('online.roomBlitz'),
  'standard' => tr('online.roomStandard'),
  'kaiserreich' => tr('online.roomKaiserreich'),
  _ => null,
};

IconData roomIcon(String? template) => switch (template) {
  'blitz' => Icons.bolt,
  'standard' => Icons.shield_outlined,
  'kaiserreich' => Icons.castle_outlined,
  _ => Icons.public,
};

/// One line describing what kind of game this room is: map size, realms,
/// turn timer, war clock — the things a player compares before joining.
String roomSummary(Map<String, dynamic> settings) {
  final size = switch (settings['map_size']) {
    'klein' => tr('setup.mapSizeSmall'),
    'mittel' => tr('setup.mapSizeMedium'),
    _ => tr('setup.mapSizeLarge'),
  };
  final hours = settings['turn_timeout_hours'] as int?;
  final timer = hours == null
      ? tr('online.noTimeLimit')
      : hours == 168
      ? tr('online.sevenDaysPerTurn')
      : tr('online.hoursPerTurn', {'hours': hours});
  final parts = [
    size,
    if (settings['realm_count'] != null)
      tr('online.realmCount', {'n': settings['realm_count']}),
    timer,
    tr('online.warMinutes', {
      'n': ((settings['war_round_timeout'] as int? ?? 600) / 60).round(),
    }),
  ];
  return parts.join(' · ');
}

/// "3 h 20 min" until [iso] — null once the instant has passed (the sweep
/// starts the room within the minute, so the UI says "jeden Moment").
String? formatCountdown(String? iso) {
  final target = iso == null ? null : DateTime.tryParse(iso);
  if (target == null) return null;
  final left = target.difference(DateTime.now().toUtc());
  if (left.isNegative) return null;
  final hours = left.inHours;
  final minutes = left.inMinutes % 60;
  return hours > 0
      ? '${tr('online.countdownHours', {'h': hours})} '
            '${tr('online.countdownMinutes', {'m': minutes})}'
      : tr('online.countdownMinutes', {'m': left.inMinutes});
}

/// How the room start is worded: a countdown once enough players joined to
/// schedule it, otherwise the seat target that triggers the start.
String roomStartLine({
  required int joined,
  required int seats,
  required String? autoStartAt,
}) {
  final countdown = formatCountdown(autoStartAt);
  if (countdown != null) return tr('online.startsIn', {'time': countdown});
  if (autoStartAt != null) return tr('online.startsMomentarily');
  return tr('online.startsAtSeats', {'n': seats});
}

/// A matchmaking room in the lobby list — deliberately set apart from the
/// player-hosted games below it: accent frame, room name, seat progress.
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.match, required this.onJoin});

  /// One entry of `GET /matches/public` (a matchmaking room, i.e. one whose
  /// `settings.template` is set).
  final Map<String, dynamic> match;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings =
        (match['settings'] as Map?)?.cast<String, dynamic>() ?? const {};
    final template = settings['template'] as String?;
    final joined = match['joined'] as int? ?? 0;
    final seats = match['seats'] as int? ?? 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onJoin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(roomIcon(template), color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      roomTitle(template) ?? tr('online.openGame'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    tr('online.seatsOf', {'n': joined, 'max': seats}),
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(roomSummary(settings), style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: seats == 0 ? 0 : joined / seats,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      roomStartLine(
                        joined: joined,
                        seats: seats,
                        autoStartAt: match['auto_start_at'] as String?,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onJoin,
                    child: Text(tr('online.join')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
