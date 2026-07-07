import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 0.1.13 online-recap fix (user report 2026-07):
/// the Kaiserwahl outcome (and every other between-turns event) never
/// reached online players. The recap baselines address events by absolute
/// position (`prunedEventCount + index`) in the MASTER log, but
/// `visibleStateFor` used to REMOVE hidden events from the middle of the
/// list — every later index shifted and the client's recap slice came up
/// empty. Hidden events are now redacted in place instead.
GameState _game() => startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;

GameEvent _hidden(int slot) => GameEvent(
    year: 1004,
    slot: slot,
    type: 'turnUpkeep',
    visibility: EventVisibility.owner);

void main() {
  group('filtered event log keeps absolute positions', () {
    test('hidden events are redacted in place, never removed', () {
      final state = _game();
      state.events.clear();
      state.events.addAll([
        _hidden(2),
        GameEvent(
            year: 1000,
            slot: 0,
            type: 'electionStarted',
            visibility: EventVisibility.public),
      ]);

      final filtered = visibleStateFor(state, 1);
      expect(filtered.events.length, state.events.length,
          reason: 'indices must match the master log');
      expect(filtered.events[0].type, 'redacted');
      expect(filtered.events[0].visibleTo(1), isFalse,
          reason: 'the placeholder never shows up in feed/recap');
      expect(filtered.events[0].payload, isEmpty,
          reason: 'no hidden information may leak through the placeholder');
      expect(filtered.events[1].type, 'electionStarted');

      // The client re-filters online states — must be idempotent.
      final twice = visibleStateFor(filtered, 1);
      expect([for (final e in twice.events) e.type],
          [for (final e in filtered.events) e.type]);
    });

    test(
        'a coronation between the player\'s turns reaches their recap slice '
        '(online Kaiserwahl regression)', () {
      final state = _game();
      state.events.clear();
      state.prunedEventCount = 40; // an older game: log partially pruned

      // History BEFORE the player's last end_turn: plenty of foreign
      // upkeep the viewer may not see — exactly what used to shift the
      // filtered indices past the whole recap.
      for (var i = 0; i < 200; i++) {
        state.events.add(_hidden(2 + i % 5));
      }
      // The server's end_turn baseline: an absolute MASTER position.
      state.recapBaselines[1] = state.prunedEventCount + state.events.length;

      // Between the turns: more hidden noise, then the Kaiserwahl result.
      state.events.add(_hidden(3));
      state.events.add(GameEvent(
          year: 1005,
          slot: 3,
          type: 'crowned',
          visibility: EventVisibility.public,
          payload: {'office': 'kaiser', 'name': 'Otto'}));

      final filtered = visibleStateFor(state, 1);

      // What GameController.recapFor computes on the client.
      final baseline = filtered.recapBaselines[1] ?? 0;
      final from = (baseline - filtered.prunedEventCount)
          .clamp(0, filtered.events.length);
      final recap = [
        for (var i = from; i < filtered.events.length; i++)
          if (filtered.events[i].visibleTo(1)) filtered.events[i],
      ];
      expect([for (final e in recap) e.type], ['crowned'],
          reason: 'the between-turns coronation is the entire recap');
    });
  });

  group('dual office holder (Kaiser converts to Islam, wins Sultanswahl)',
      () {
    test('CollectTribute empties BOTH pots — and never throws on one '
        'empty pot while the other is filled (AI turn-start crash)', () {
      final state = _game();
      final ruler = state.realm(1).rulerId;
      state.kaiserId = ruler;
      state.sultanId = ruler;
      state.kaiserPot = 0; // exactly the crash constellation: the AI
      state.sultanPot = 400; // collects because the SULTAN pot is filled
      final before = state.realm(1).treasury;

      final result = applyAction(state, CollectTribute(slot: 1), Rng(1));
      expect(result.state.realm(1).treasury, before + 400);
      expect(result.state.sultanPot, 0);
      expect(result.events.single.payload['office'], 'sultan');

      // Both pots filled: one action, both collected, one event each.
      state.kaiserPot = 300;
      state.sultanPot = 500;
      final both = applyAction(state, CollectTribute(slot: 1), Rng(1));
      expect(both.state.realm(1).treasury, before + 800);
      expect(both.state.kaiserPot, 0);
      expect(both.state.sultanPot, 0);
      expect([for (final e in both.events) e.payload['office']],
          ['kaiser', 'sultan']);

      // Truly empty still rejects.
      expect(() => applyAction(both.state, CollectTribute(slot: 1), Rng(1)),
          throwsA(isA<ActionException>()));
    });

    test('death in double office vacates and chronicles both', () {
      final state = _game();
      final ruler = state.person(state.realm(1).rulerId)!;
      state.kaiserId = ruler.id;
      state.sultanId = ruler.id;

      final events = <GameEvent>[];
      closeChronicleIfOfficeHolder(state, ruler, Rng(1), events);
      expect(state.kaiserId, isNull);
      expect(state.sultanId, isNull,
          reason: 'a dead Sultan would block every future Sultanswahl');
      expect(state.kaiserChronicle.last.deathYear, state.year);
      expect(state.sultanChronicle.last.deathYear, state.year);
      expect(events.where((e) => e.type == 'officeHolderDied').length, 2);
    });
  });
}
