import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for the 2026-07-14 root-cause cleanup round.
///
/// A human slot 1 next to a second slot 2, sharing a border — mirrors the
/// war_test setUp. Both have a 50-man infantry unit and 10,000 T.
GameState warReadyGame() {
  var state = startGame(
          newGame(GameSetup(
            humans: [
              HumanPlayerSetup(
                  founderName: 'Anna',
                  gender: 1,
                  countrySlot: 1,
                  dorfName: 'A'),
              HumanPlayerSetup(
                  founderName: 'Berta',
                  gender: 1,
                  countrySlot: 2,
                  dorfName: 'B'),
            ],
            reformationYear: 1020,
            ottomanYear: 1040,
            seed: 2026,
          )),
          Rng(7))
      .state;
  state.year = 1010;
  for (final slot in [1, 2]) {
    final realm = state.realm(slot);
    realm.treasury = 10000;
    realm.towns.single.troopCapacity = 200;
    realm.troopCapacity = 200;
    state = applyAction(
            state,
            RecruitTroops(
                slot: slot,
                men: 50,
                troopClass: TroopClass.infanterie,
                name: 'Heer$slot'),
            Rng(state.rngSeed))
        .state;
  }
  // Hand slot 2 a land tile right next to slot 1's territory (shared border).
  final map = state.map;
  outer:
  for (var y = 0; y < map.height; y++) {
    for (var x = 0; x < map.width; x++) {
      if (map.ownerAt(x, y) != World.niemand || map.isWaterAt(x, y)) continue;
      if (map.bordersSlot(x, y, 1)) {
        map.owner[map.index(x, y)] = 2;
        state.realm(2).tileCount[Building.none]++;
        break outer;
      }
    }
  }
  return state;
}

void main() {
  test(
      'a DELEGATED human war side is really autopiloted — its WarMoves are '
      'not rejected as out-of-turn input', () {
    // Both sides human → the war starts in preparation.
    var s = warReadyGame();
    s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
        .state;
    final war = s.activeWar!;
    expect(war.phase, WarPhase.preparation);

    // The defender hands this war to the stance autopilot; the attacker
    // plays live (so the defender's moves run OUT of the acting turn).
    war.autoSlots.add(2);
    s.pendingDecisions.removeWhere((d) => d.type == 'warPlan');
    beginWarRounds(s, Rng(s.rngSeed));
    expect(warActingSlot(s), 1, reason: 'the live attacker is awaited');

    for (final troop in s.realm(2).troops) {
      troop.stance = TroopStance.attack; // march on the enemy capital
    }
    final unit = s.realm(2).troops.first;
    final before = (unit.x, unit.y);

    final events = <GameEvent>[];
    endWarRoundWithAi(s, Rng(s.rngSeed), events);

    final after = (s.realm(2).troops.first.x, s.realm(2).troops.first.y);
    expect(after, isNot(equals(before)),
        reason: 'the autopilot must move the delegated side — before the '
            '_warFor fix every one of its WarMoves threw "Dein Gegner ist '
            'gerade am Zug !" and was silently swallowed');
  });

  test(
      'WarMarch walks a unit toward the target across several steps in one '
      'action, tracking it by identity', () {
    var s = warReadyGame();
    s.dynasty(2).status = DynastyStatus.ai;
    s.dynasty(2).humanPlayer = null;
    s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
        .state;
    final realm = s.realm(1);
    final unit = realm.troops.first;
    expect(unit.id, greaterThan(0), reason: 'recruits get stable ids');
    final enemy = s.realm(2);
    final before =
        (unit.x - enemy.capitalX).abs() + (unit.y - enemy.capitalY).abs();
    expect(before, greaterThan(1), reason: 'a real march, not one step');

    final result = applyAction(
        s,
        WarMarch(slot: 1, unitIndex: 0, x: enemy.capitalX, y: enemy.capitalY),
        Rng(s.rngSeed));

    final after = result.state.realm(1).troops.first;
    final remaining =
        (after.x - enemy.capitalX).abs() + (after.y - enemy.capitalY).abs();
    expect(remaining, lessThan(before),
        reason: 'the march covered more than a single tap-step');
  });

  test('WarMarch with no passable path rejects instead of burning moves', () {
    var s = warReadyGame();
    s.dynasty(2).status = DynastyStatus.ai;
    s.dynasty(2).humanPlayer = null;
    s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
        .state;
    // A water tile is never reachable over land.
    final map = s.map;
    var wx = -1, wy = -1;
    outer:
    for (var y = 0; y < map.height; y++) {
      for (var x = 0; x < map.width; x++) {
        if (map.isWaterAt(x, y)) {
          wx = x;
          wy = y;
          break outer;
        }
      }
    }
    expect(
        () => applyAction(
            s, WarMarch(slot: 1, unitIndex: 0, x: wx, y: wy), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()));
  });

  test(
      'a war side stripped of its last land mid-war is vacated at the war '
      'teardown, not at the next round sweep', () {
    var s = warReadyGame();
    // Slot 2 plays AI so the war goes straight to rounds.
    s.dynasty(2).status = DynastyStatus.ai;
    s.dynasty(2).humanPlayer = null;
    s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
        .state;
    expect(s.activeWar, isNotNull);

    // Plunder-style total loss: every slot-2 tile falls to no-man's-land.
    final map = s.map;
    for (var i = 0; i < map.owner.length; i++) {
      if (map.owner[i] == 2) {
        map.owner[i] = World.niemand;
        map.building[i] = Building.none;
      }
    }
    final loser = s.realm(2);
    for (var b = 0; b < loser.tileCount.length; b++) {
      loser.tileCount[b] = 0;
    }
    loser.towns.clear();

    // Neither side stands on enemy land → 0:0 scores → draw teardown.
    final events = <GameEvent>[];
    resolveWarEnd(s, Rng(s.rngSeed), events);

    expect(s.activeWar, isNull);
    expect(events.any((e) => e.type == 'warDraw'), isTrue);
    expect(s.realm(2).isVacant, isTrue,
        reason: 'the landless side is vacated by the teardown itself — the '
            'old once-per-round sweep left it as a zombie until the next '
            'round start');
    expect(events.any((e) => e.type == 'realmOverrun'), isTrue);
  });
}
