import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// User reports (2026-07-24), all rooted in the §14.2 patrilineal marriage
/// model: a human female ruler married to a foreign (AI) king lost her
/// children to his house — she could neither name them nor see them in her
/// Dynastie sheet, and her own line was left heirless, so her realm passed to
/// the AI husband (surfacing as "I killed my husband and was immediately
/// defeated").
///
/// Fix (gated on the gender-equal succession match setting): under
/// gender-equal succession a ruling queen keeps her OWN line. Strict
/// patrilineal — the default — is unchanged (see [bugfix_v24_defeat_reason]).
GameState _game({
  int seed = 2026,
  int gender = 1, // 1 = female founder ruling slot 1 (BB)
  bool genderEqualSuccession = true,
}) =>
    newGame(GameSetup(
      humans: [
        HumanPlayerSetup(
          founderName: 'Koenigin',
          gender: gender,
          countrySlot: 1,
          dorfName: 'Burg',
        ),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: seed,
      genderEqualSuccession: genderEqualSuccession,
    ));

/// A male king ruling the (AI) slot [slot], stripped to just himself so
/// succession has a clean, predictable member set.
Person _foreignKing(GameState state, int slot) {
  for (final id in List.of(state.dynasty(slot).memberIds)) {
    state.persons.remove(id);
    state.dynasty(slot).memberIds.remove(id);
  }
  final king = Person(
      id: state.nextPersonId++, name: 'Koenig', age: 35, dynasty: slot, gender: 0);
  state.persons[king.id] = king;
  state.dynasty(slot).memberIds.add(king.id);
  state.realm(slot).rulerId = king.id;
  return king;
}

void main() {
  group('gender-equal: a queen married to a foreign king keeps her line', () {
    test('bug 2: her child joins HER dynasty and SHE is prompted to name it',
        () {
      final state = startGame(_game(), Rng(1)).state;
      state.year = 1005; // protection window — no death rolls to disturb us
      final queen = state.person(state.realm(1).rulerId)!;
      final king = _foreignKing(state, 2);
      expect(state.dynasty(2).status, DynastyStatus.ai);
      marry(state, queen, king, <GameEvent>[]);

      // Births fire from the husband's (AI) turn; run it until one lands.
      PendingDecision? childName;
      for (var i = 0; i < 400 && childName == null; i++) {
        runDynastyPhase(state, 2, Rng(i), <GameEvent>[]);
        final hits =
            state.pendingDecisions.where((d) => d.type == 'childName');
        childName = hits.isEmpty ? null : hits.first;
      }
      expect(childName, isNotNull,
          reason: 'the queen must be prompted to name her child');
      // Routed to the QUEEN's slot (not the AI husband's), so she can answer.
      expect(childName!.decidingSlot, queen.dynasty);
      final childId = childName.payload['childId'] as int;
      // The child is a member of HER dynasty → visible in her Dynastie sheet.
      expect(state.persons[childId]!.dynasty, queen.dynasty);
      expect(state.dynasty(queen.dynasty).memberIds, contains(childId));
      // No premature public 'birth' event leaked (deferred to the naming).
      expect(state.persons[childId]!.dynasty, isNot(2));
    });

    test('bug 3: assassinating the husband hands his realm to their child '
        'under HER control — not a defeat', () {
      final state = startGame(_game(), Rng(1)).state;
      state.year = 1010;
      final queen = state.person(state.realm(1).rulerId)!;
      final king = _foreignKing(state, 2);
      queen.spouseId = king.id;
      king.spouseId = queen.id;
      // Their child, in the QUEEN's line (as the fixed _birth would place it).
      final child = Person(
          id: state.nextPersonId++,
          name: 'Kind',
          age: 8,
          dynasty: queen.dynasty,
          gender: 0);
      state.persons[child.id] = child;
      state.dynasty(queen.dynasty).memberIds.add(child.id);
      queen.childrenIds.add(child.id);
      king.childrenIds.add(child.id);

      // The assassination outcome: the husband dies.
      handleDeath(state, king, Rng(5), <GameEvent>[]);

      // Kurpfalz passes to their child and, being of the queen's house,
      // it is played by the queen's own player.
      expect(state.realm(2).rulerId, child.id);
      expect(state.dynasty(2).status, DynastyStatus.human);
      expect(state.dynasty(2).humanPlayer, state.dynasty(1).humanPlayer);
      // BB is untouched and the queen is NOT defeated.
      expect(state.dynasty(1).status, DynastyStatus.human);
      expect(state.humanLossReason, isNull);
      final humanSeated = state.realms.any((r) =>
          !r.isVacant && state.dynasty(r.slot).status == DynastyStatus.human);
      expect(humanSeated, isTrue);
    });

    test('a married queen\'s own child inherits HER realm (line not heirless)',
        () {
      final state = startGame(_game(), Rng(1)).state;
      state.year = 1010;
      final queen = state.person(state.realm(1).rulerId)!;
      final king = _foreignKing(state, 2);
      queen.spouseId = king.id;
      king.spouseId = queen.id;
      final child = Person(
          id: state.nextPersonId++,
          name: 'Kind',
          age: 8,
          dynasty: queen.dynasty,
          gender: 0);
      state.persons[child.id] = child;
      state.dynasty(queen.dynasty).memberIds.add(child.id);
      queen.childrenIds.add(child.id);
      king.childrenIds.add(child.id);

      handleDeath(state, queen, Rng(5), <GameEvent>[]);

      // Her child inherits BB and the seat stays human — no realmInherited
      // flip to the foreign house.
      expect(state.realm(1).rulerId, child.id);
      expect(state.dynasty(1).status, DynastyStatus.human);
      expect(state.humanLossReason, isNull);
    });
  });

  group('default (patrilineal) is unchanged', () {
    test('with the setting OFF, a married queen\'s realm still passes to the '
        'foreign spouse', () {
      final state =
          startGame(_game(genderEqualSuccession: false), Rng(1)).state;
      state.year = 1010;
      final queen = state.person(state.realm(1).rulerId)!;
      final king = _foreignKing(state, 2);
      queen.spouseId = king.id;
      king.spouseId = queen.id;
      // A daughter in her dynasty — under strict §15.4 she is skipped.
      final daughter = Person(
          id: state.nextPersonId++,
          name: 'Tochter',
          age: 12,
          dynasty: 1,
          gender: 1);
      state.persons[daughter.id] = daughter;
      state.dynasty(1).memberIds.add(daughter.id);
      queen.childrenIds.add(daughter.id);

      handleDeath(state, queen, Rng(5), <GameEvent>[]);

      expect(state.realm(1).rulerId, king.id,
          reason: 'realm falls to the foreign spouse (rank 3)');
      expect(state.dynasty(1).status, DynastyStatus.ai);
      expect(state.humanLossReason, 'realmInherited');
    });
  });
}
