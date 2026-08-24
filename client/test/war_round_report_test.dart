import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:pckaiser/widgets/decisions.dart';

/// The war-turn round report renders the recap, and the recap carries
/// every PUBLIC event — including war news from realms the player is not
/// fighting. `[FIX 2026-08-24, user report]`: a foreign war ending in
/// winter popped "Der Krieg musste wegen des hereinbrechenden Winters
/// beendet werden" in the first round of the player's own war.
void main() {
  final war = ActiveWar(attackerSlot: 2, defenderSlot: 1);

  GameEvent event(
    String type,
    int slot, {
    List<int> participants = const [],
    Map<String, dynamic> payload = const {},
  }) => GameEvent(
    year: 1000,
    slot: slot,
    type: type,
    visibility: EventVisibility.public,
    participants: participants,
    payload: payload,
  );

  test('a foreign war ending in winter stays out of the round report', () {
    final winter = event('winterEndsWar', 0);
    expect(roundReportEvents(war, [winter]), isEmpty);
  });

  test('a foreign war\'s end and battles stay out too', () {
    final foreign = [
      event('battle', 7, participants: [7, 8]),
      event(
        'warWon',
        7,
        payload: {
          'loserSlot': 8,
          'summary': {'attackerSlot': 7, 'defenderSlot': 8},
        },
      ),
      event(
        'warDraw',
        0,
        payload: {
          'summary': {'attackerSlot': 7, 'defenderSlot': 8},
        },
      ),
    ];
    expect(roundReportEvents(war, foreign), isEmpty);
  });

  test('the own war\'s events are kept', () {
    final own = [
      event('battle', 2, participants: [1, 2]),
      event('plunder', 2),
      event('capitalHeld', 2, payload: {'loserSlot': 1}),
      event(
        'peaceAgreed',
        0,
        participants: [1, 2],
        payload: {
          'summary': {'attackerSlot': 2, 'defenderSlot': 1},
        },
      ),
    ];
    expect(roundReportEvents(war, own), hasLength(own.length));
  });
}
