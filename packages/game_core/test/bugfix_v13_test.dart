import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Rules v13 round: militarism popularity costs (war declaration −10,
/// levies −(1 + men/200)) and the capture-claim floor (a capture victory
/// can always afford the loser's capital tile).
void main() {
  late GameState state;

  setUp(() {
    state = startGame(
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
    // Human-vs-human wars are blocked in V1: slot 2 plays AI-controlled.
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
    for (final slot in [1, 2]) {
      final realm = state.realm(slot);
      realm.treasury = 50000;
      realm.towns.single.troopCapacity = 1000;
      realm.troopCapacity = 1000;
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
    // Wars need a shared border: hand slot 2 a land tile next to slot 1.
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
    expect(state.map.realmNeighbors(1), contains(2));
  });

  group('militarism popularity costs (rules v13)', () {
    test('declaring war costs the attacker 5 popularity', () {
      state.realm(1).popularity = 50;
      state.realm(2).popularity = 50;
      final s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      expect(s.realm(1).popularity, 45);
      expect(s.realm(2).popularity, 50,
          reason: 'the defender is the victim — no popularity hit');
    });

    test('levies floor at 25, war declarations at 10 (0.1.13)', () {
      // Already below the floor (food crisis): untouched, never raised.
      state.realm(1).popularity = 12;
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'R'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).popularity, 12);

      // War declarations bypass the militarism floor down to 10 — repeated
      // aggression may cross the §19.1 strife line (user feedback 0.1.13).
      s.realm(1).popularity = 27;
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      expect(s.realm(1).popularity, 22,
          reason: 'the war floor (10) sits below the strife line');

      // A single declaration never zeroes the stat: floored at 10.
      s.realm(1).popularity = 12;
      s.realm(1).warThisYear = false;
      s.activeWar = null;
      s.year++; // a new year, but recentWars persists via warThisYear reset
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      expect(s.realm(1).popularity, 10);
    });

    test('recruiting costs 1 + men/200 popularity', () {
      state.realm(1).popularity = 50;
      // Levy limit: the setUp already levied 50 this turn — enough people
      // that the 50 + 400 recruits below fit into this year's 10% levy.
      state.realm(1).towns.single.population += 5000;
      state.realm(1).population += 5000;
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 50,
                  troopClass: TroopClass.infanterie,
                  name: 'R'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).popularity, 49);

      s.realm(1).popularity = 50;
      s = applyAction(
              s,
              RecruitTroops(
                  slot: 1,
                  men: 400,
                  troopClass: TroopClass.infanterie,
                  name: 'R'),
              Rng(s.rngSeed))
          .state;
      expect(s.realm(1).popularity, 47);
    });

    test('hiring Söldner costs the same levy popularity', () {
      state.realm(1).popularity = 50;
      final s = applyAction(state, HireSoeldner(slot: 1, men: 200, name: 'S'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).popularity, 48);
    });
  });

  group('capture claim floor (rules v13)', () {
    /// Declares war (slot 1 → slot 2) and parks slot 1's unit on slot 2's
    /// capital; the defender's unit is moved aside first.
    GameState marchOntoCapital(GameState from) {
      var s = applyAction(
              from, DeclareWar(slot: 1, targetSlot: 2), Rng(from.rngSeed))
          .state;
      final enemy = s.realm(2);
      enemy.troops.single.x = enemy.towns.single.x;
      enemy.troops.single.y = enemy.towns.single.y;
      final troop = s.realm(1).troops.single;
      troop.x = enemy.capitalX - 1;
      troop.y = enemy.capitalY;
      s.activeWar!.movesLeft[1]![0] = 5;
      return applyAction(
              s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed))
          .state;
    }

    test(
        'a capture claim always covers the loser capital tile, even when '
        'the v12 cap is smaller', () {
      var s = marchOntoCapital(state);
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      // Strip slot 2 down to capital + Dorf + one further tile before the
      // capture resolves. That kept tile becomes a BURG: key points are
      // Stadt/Burg/Palast only (user rule 2026-07-13) — with the occupied
      // seat as the loser's only stronghold the whole realm would be
      // annexed instead of opening this settlement.
      final map = s.map;
      final loser = s.realm(2);
      var keptIndex = -1;
      for (var i = 0; i < map.terrain.length; i++) {
        if (map.owner[i] != 2) continue;
        final isCapital = i == map.index(loser.capitalX, loser.capitalY);
        if (keptIndex < 0 && !isCapital && map.building[i] == Building.none) {
          keptIndex = i;
          continue;
        }
        if (isCapital || map.building[i] == Building.dorf) continue;
        loser.tileCount[map.building[i]]--;
        map.owner[i] = World.niemand;
      }
      expect(keptIndex, greaterThanOrEqualTo(0));
      map.building[keptIndex] = Building.burg;
      loser.tileCount[Building.none]--;
      loser.tileCount[Building.burg]++;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.winnerSlot, 1);
      final capitalValue = settlementTileValue(
          s, s.map.buildingAt(loser.capitalX, loser.capitalY));
      expect(s.activeWar!.remainingClaim, greaterThanOrEqualTo(capitalValue),
          reason: 'the captor held the seat — taking it must be possible');
    });
  });
}
