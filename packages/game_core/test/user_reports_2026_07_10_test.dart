import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// User-report round 2026-07-10 (docs/HISTORY.md):
///  1. faith may be chosen in the Reformation year itself (off-by-one),
///  2. a married woman's realms fall to her widower, not her sons (§14.2:
///     the couple's children hang on the HUSBAND's list),
///  3. every ARMY plunders once per war round (was: once per side).
/// (The other two fixes of the round have their tests elsewhere:
/// per-person marriage proposals in actions_test.dart, the §11.2
/// whole-realm ruler capture in war_test.dart.)
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
            newGame(GameSetup(
              humans: [
                HumanPlayerSetup(
                    founderName: 'Hans',
                    gender: 0,
                    countrySlot: 1,
                    dorfName: 'A'),
              ],
              reformationYear: 1020,
              ottomanYear: 1040,
              seed: 2026,
            )),
            Rng(7))
        .state;
    state.realm(1).treasury = 10000;
  });

  group('religion change at the Reformation (report 1)', () {
    test('blocked the year BEFORE the Reformation', () {
      state.year = 1019;
      expect(
          () => applyAction(
              state,
              ChangeReligion(slot: 1, religion: Religion.evangelisch),
              Rng(1)),
          throwsA(isA<ActionException>()));
    });

    test('allowed in the Reformation year itself', () {
      state.year = 1020;
      final result = applyAction(state,
          ChangeReligion(slot: 1, religion: Religion.evangelisch), Rng(1));
      expect(result.state.dynasty(1).religion, Religion.evangelisch);
      expect(result.events.any((e) => e.type == 'religionChanged'), isTrue);
    });

    test('Islam allowed in the Ottoman year itself', () {
      state.year = 1040;
      final result = applyAction(state,
          ChangeReligion(slot: 1, religion: Religion.moslemisch), Rng(1));
      expect(result.state.dynasty(1).religion, Religion.moslemisch);
    });
  });

  group('a married woman\'s realms fall to her widower (report 2)', () {
    test('the husband inherits ahead of the couple\'s son', () {
      final hans = state.persons[state.realm(1).rulerId]!;

      // A wife from another house who came to rule slot 2 (the §15.4
      // spouse path in reverse: her own house died out around her).
      final wife = Person(
          id: state.nextPersonId++,
          name: 'Uta',
          age: hans.age,
          dynasty: 2,
          gender: 1);
      state.persons[wife.id] = wife;
      final herHouse = state.dynasty(2);
      for (final id in List.of(herHouse.memberIds)) {
        if (state.persons[id] != null) {
          state.dynasty(2).memberIds.remove(id);
          state.persons.remove(id);
        }
      }
      herHouse.memberIds.add(wife.id);
      state.realm(2).rulerId = wife.id;
      marry(state, hans, wife, <GameEvent>[]);

      // The couple's son — deliberately double-linked on BOTH parents'
      // children lists, like every save written before 2026-07-10.
      final son = Person(
          id: state.nextPersonId++,
          name: 'Junior',
          age: 20,
          dynasty: 1,
          gender: 0);
      state.persons[son.id] = son;
      state.dynasty(1).memberIds.add(son.id);
      hans.childrenIds.add(son.id);
      wife.childrenIds.add(son.id);

      handleDeath(state, wife, Rng(3), <GameEvent>[]);

      expect(state.realm(2).rulerId, hans.id,
          reason: 'the widower (§15.4 rank 3) inherits — the son ranks '
              'via the HUSBAND\'s children list only (§14.2)');
    });

    test('a deceased HUSBAND\'s realms still go to his son first', () {
      final hans = state.persons[state.realm(1).rulerId]!;
      final wife = Person(
          id: state.nextPersonId++,
          name: 'Uta',
          age: hans.age,
          dynasty: 2,
          gender: 1);
      state.persons[wife.id] = wife;
      state.dynasty(2).memberIds.add(wife.id);
      marry(state, hans, wife, <GameEvent>[]);

      final son = Person(
          id: state.nextPersonId++,
          name: 'Junior',
          age: 20,
          dynasty: 1,
          gender: 0);
      state.persons[son.id] = son;
      state.dynasty(1).memberIds.add(son.id);
      hans.childrenIds.add(son.id);

      handleDeath(state, hans, Rng(3), <GameEvent>[]);

      expect(state.realm(1).rulerId, son.id,
          reason: '§15.4 rank 1: the first male child inherits');
    });
  });

  group('plunder once per ARMY per round (report 5)', () {
    late GameState s;
    late int tx, ty;

    setUp(() {
      state.year = 1010;
      state.dynasty(2).status = DynastyStatus.ai;
      state.dynasty(2).humanPlayer = null;
      final realm = state.realm(1);
      realm.towns.single.troopCapacity = 500;
      realm.troopCapacity = 500;
      for (final name in ['Erste', 'Zweite']) {
        state = applyAction(
                state,
                RecruitTroops(
                    slot: 1,
                    men: 50,
                    troopClass: TroopClass.infanterie,
                    name: name),
                Rng(state.rngSeed))
            .state;
      }
      // Wars need a shared border: hand slot 2 a tile next to slot 1.
      final map = state.map;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              map.owner[map.index(x, y)] = 2;
              state.realm(2).tileCount[Building.none]++;
              break outer;
            }
          }
        }
      }
      s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // Park both armies on the enemy town (a plunderable building).
      final town = s.realm(2).towns.single;
      tx = town.x;
      ty = town.y;
      for (final troop in s.realm(1).troops) {
        troop.x = tx;
        troop.y = ty;
      }
      s.rebuildTroopMarkers();
    });

    test('both armies may plunder in the same round; then it is spent', () {
      s = applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(1)).state;
      // The second ARMY still has its plunder — this used to throw.
      s = applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(2)).state;
      expect(s.realm(1).troops.every((t) => t.plunderedThisRound), isTrue);
      expect(
          () => applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(3)),
          throwsA(isA<ActionException>()));
    });

    test('the round advance restores every army\'s plunder', () {
      s = applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(1)).state;
      s = applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(2)).state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      expect(s.activeWar, isNotNull);
      expect(s.realm(1).troops.any((t) => t.plunderedThisRound), isFalse);
      // A fresh round, a fresh plunder for the same army.
      final result = applyAction(s, WarPlunder(slot: 1, x: tx, y: ty), Rng(4));
      expect(result.events.any((e) => e.type == 'plunder'), isTrue);
    });
  });
}
