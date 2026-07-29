/// System-hosted matchmaking rooms ("offizielle Partien"): instead of
/// sharing a room code, players join one of a handful of permanently open
/// matches the SERVER hosts. There is always exactly one open room per
/// template — the moment one starts, the next is created (see
/// `MatchService.ensureTemplateMatches`), so the lobby never fragments the
/// player base across several half-full rooms of the same kind.
///
/// A template room has no creator: nobody may start it by hand, nobody
/// deletes it by leaving. It starts on its own — either when [seats] is
/// reached, or [fallbackDelay] after the [fallbackSeats]-th player joined,
/// with the remaining realms staying AI (a match is fully playable with
/// fewer humans; the AI plays the rest of the world either way).
library;

import 'models.dart';

/// One matchmaking room type. The settings not listed here are deliberately
/// the plain defaults (AI difficulty `mittel`, the standard event years,
/// gender-equal succession) — parameters nobody compares in a lobby line.
class MatchTemplate {
  const MatchTemplate({
    required this.key,
    required this.mapSize,
    required this.realmCount,
    required this.seats,
    required this.fallbackSeats,
    required this.turnTimeoutHours,
    required this.warRoundTimeoutSeconds,
  });

  /// Stable identifier, stored in `settings.template` and sent to the
  /// client, which localizes it (never send a display name — the UI is
  /// bilingual, see CLAUDE.md).
  final String key;

  /// `klein` | `mittel` | `gross` (`MapSize` in game_core).
  final String mapSize;

  final int realmCount;

  /// Human seats: reaching this starts the match immediately.
  final int seats;

  /// Once this many players have joined, the room starts [fallbackDelay]
  /// later even if it never fills — otherwise the biggest room would wait
  /// forever for its last seat and block the template.
  final int fallbackSeats;

  final int turnTimeoutHours;
  final int warRoundTimeoutSeconds;

  /// Grace period after the [fallbackSeats]-th join before the room starts
  /// without being full.
  static const Duration fallbackDelay = Duration(hours: 24);

  /// Settings for a fresh room of this type (a new random seed per room).
  MatchSettings newSettings() => MatchSettings(
        turnTimeoutHours: turnTimeoutHours,
        warRoundTimeoutSeconds: warRoundTimeoutSeconds,
        mapSize: mapSize,
        realmCount: realmCount,
        isPublic: true,
        template: key,
      );
}

/// The rooms the server keeps open, in lobby order (fastest first).
const List<MatchTemplate> matchTemplates = [
  MatchTemplate(
    key: 'blitz',
    mapSize: 'klein',
    realmCount: 12,
    seats: 4,
    fallbackSeats: 3,
    turnTimeoutHours: 12,
    warRoundTimeoutSeconds: 300,
  ),
  MatchTemplate(
    key: 'standard',
    mapSize: 'mittel',
    realmCount: 20,
    seats: 6,
    fallbackSeats: 4,
    turnTimeoutHours: 24,
    warRoundTimeoutSeconds: 600,
  ),
  MatchTemplate(
    key: 'kaiserreich',
    mapSize: 'gross',
    realmCount: 30,
    seats: 10,
    fallbackSeats: 6,
    turnTimeoutHours: 24,
    warRoundTimeoutSeconds: 600,
  ),
];

/// The template a match belongs to, or null for an ordinary (player-hosted)
/// match. A stored key that no longer exists — a template removed in a later
/// build — degrades to "ordinary match" rather than breaking the room.
MatchTemplate? templateFor(MatchSettings settings) {
  final key = settings.template;
  if (key == null) return null;
  for (final t in matchTemplates) {
    if (t.key == key) return t;
  }
  return null;
}
