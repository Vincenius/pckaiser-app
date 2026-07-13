import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// The `humansDefeated` screen must name the cause of the PLAYER's own loss,
/// not whatever control-losing event happens to be most recent in the shared
/// log. Regression for the report: a Brandenburg player (female ruler, heirs
/// alive, no war) saw "Dein Herrscher wurde im Krieg gefangen genommen" with
/// the inheriting AI realm on screen — the old `_defeatReason` had scanned the
/// whole log backwards and matched an unrelated AI-vs-AI `rulerCaptured`.
///
/// The cause is now recorded at the moment each human seat falls
/// (`GameState.humanLossReason`).
GameState _game({int seed = 2026}) => newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
            founderName: 'Königin',
            gender: 1,
            countrySlot: 1,
            dorfName: 'Burg'),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: seed,
      // The first test needs the faithful §15.4 male-priority rules so the
      // daughter is skipped and the realm falls to the foreign spouse.
      genderEqualSuccession: false,
    ));

void main() {
  group('humansDefeated reason reflects the human seat that fell', () {
    test(
        'a foreign spouse inheriting the realm reports realmInherited, not '
        'a stray AI war capture', () {
      final state = startGame(_game(), Rng(1)).state;
      state.year = 1010;

      // The human ruler (slot 1) is a woman married into an AI house (slot 2);
      // she has only a daughter, so the §15.4 heir priority falls through to
      // the spouse — the realm passes to the AI house and slot 1 flips to AI.
      final queen = state.person(state.realm(1).rulerId)!;
      final foreignKing = state.person(state.realm(2).rulerId)!;
      queen.spouseId = foreignKing.id;
      foreignKing.spouseId = queen.id;
      final daughter = Person(
          id: state.nextPersonId++,
          name: 'Tochter',
          age: 12,
          dynasty: 1,
          gender: 1);
      state.persons[daughter.id] = daughter;
      state.dynasty(1).memberIds.add(daughter.id);
      queen.childrenIds.add(daughter.id);

      // A pre-existing, unrelated AI-vs-AI capture sits in the shared log —
      // exactly what the old scan would have wrongly latched onto.
      state.events.add(GameEvent(
        year: 1009,
        slot: 5,
        type: 'rulerCaptured',
        visibility: EventVisibility.public,
        payload: {'loserSlot': 6, 'loserHuman': false},
      ));

      final events = <GameEvent>[];
      handleDeath(state, queen, Rng(5), events);

      // Precondition: the seat really did flip to the AI house.
      expect(state.dynasty(1).status, DynastyStatus.ai,
          reason: 'the realm passed to the foreign (AI) spouse');
      expect(state.humanLossReason, 'realmInherited');

      // 2026-07-13: the loss also announces itself — the affected player
      // gets an explicit public event (the client shows it as a popup)
      // instead of the realm silently flipping to the AI.
      final seatLost = events.singleWhere((e) => e.type == 'seatLost');
      expect(seatLost.slot, 1);
      expect(seatLost.payload['reason'], 'realmInherited');

      // The defeat event carries the inheritance cause — never the unrelated
      // war capture still sitting in the log.
      final defeat = advanceUntilHuman(state, Rng(5))
          .events
          .firstWhere((e) => e.type == 'humansDefeated');
      expect(defeat.payload['reason'], 'realmInherited');
      expect(defeat.payload['reason'], isNot('rulerCaptured'));
    });

    test('an AI-vs-AI capture never sets a defeat reason for the human', () {
      final state = startGame(_game(), Rng(1)).state;
      state.year = 1010;
      // Slot 2 (AI) captures slot 3 (AI): a human seat is untouched, so the
      // player's defeat reason must stay unset.
      state.noteHumanSeatLost(2, 'rulerCaptured');
      expect(state.humanLossReason, isNull,
          reason: 'slot 2 is AI — its loss is not the human\'s defeat');
    });
  });
}
