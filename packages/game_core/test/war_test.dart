import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

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
    // Human-vs-human wars are blocked in V1 (online war clock pending):
    // the war tests run human slot 1 against an AI-controlled slot 2.
    state.dynasty(2).status = DynastyStatus.ai;
    state.dynasty(2).humanPlayer = null;
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
    // Wars need a shared border: hand slot 2 a land tile right next to
    // slot 1's territory.
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

  group('troops (§10)', () {
    test('recruiting quarters men in towns and respects capacity', () {
      final realm = state.realm(1);
      expect(realm.troops, hasLength(1));
      expect(realm.armySize, 50);
      expect(realm.towns.single.garrison, 50);
      expect(realm.treasury, 10000 - 250);
      expect(
        () => applyAction(
            state,
            RecruitTroops(slot: 1, men: 151, troopClass: 0, name: 'Zuviel'),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'capacity 200, garrison 50',
      );
    });

    test('cavalry surcharge, Söldner outside the garrison', () {
      var s = applyAction(
              state,
              RecruitTroops(
                  slot: 1,
                  men: 10,
                  troopClass: TroopClass.kavallerie,
                  name: 'Reiter'),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).treasury, 9750 - 50 - 500);

      s = applyAction(s, HireSoeldner(slot: 1, men: 20, name: 'Mietlinge'),
              Rng(s.rngSeed))
          .state;
      expect(s.realm(1).treasury, 9200 - 1000);
      expect(s.realm(1).armySize, 60, reason: 'Söldner not garrison-counted');
      final soeldner = s.realm(1).troops.last;
      expect(soeldner.quality, TroopQuality.soeldner);
      expect(soeldner.garrisonCounted, isFalse);
    });

    test('merge requires same kind; disband releases the garrison', () {
      var s = applyAction(
              state,
              RecruitTroops(slot: 1, men: 30, troopClass: 0, name: 'Zweite'),
              Rng(state.rngSeed))
          .state;
      s = applyAction(s, MergeTroops(slot: 1, fromIndex: 1, toIndex: 0), Rng(1))
          .state;
      expect(s.realm(1).troops.single.men, 80);

      s = applyAction(s, DisbandTroop(slot: 1, unitIndex: 0), Rng(1)).state;
      expect(s.realm(1).troops, isEmpty);
      expect(s.realm(1).armySize, 0);
      expect(s.realm(1).towns.single.garrison, 0);
    });
  });

  group('war (§11)', () {
    test('war needs a shared border', () {
      // Pick a living realm that does NOT touch slot 1's territory.
      final neighbors = state.map.realmNeighbors(1);
      final distant = state.realms
          .firstWhere(
              (r) => r.slot != 1 && !r.isVacant && !neighbors.contains(r.slot))
          .slot;
      expect(
        () => applyAction(state, DeclareWar(slot: 1, targetSlot: distant),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Du hast keine gemeinsame Grenze !',
      );
    });

    test('declaration gates: year, once-per-year, troops', () {
      state.year = 1009;
      expect(
        () => applyAction(
            state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Kriege sind erst ab dem Jahr 1010 erlaubt !',
      );
      state.year = 1010;
      state.realm(1).warThisYear = true;
      expect(
        () => applyAction(
            state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      state.realm(1).warThisYear = false;
      final s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      expect(s.activeWar, isNotNull);
      expect(s.activeWar!.attackerSlot, 1);
      expect(s.realm(1).warThisYear, isTrue);
      expect(s.activeWar!.snapshots[1], hasLength(1));
    });

    test('combat applies the defense-scaled losses and never both wipe', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final a = s.realm(1).troops.single;
      final b = s.realm(2).troops.single;
      // Put the defender on its Burg (def 3+terrain) and the attacker
      // next to it.
      b.x = s.realm(2).capitalX;
      b.y = s.realm(2).capitalY;
      a.x = b.x - 1;
      a.y = b.y;
      s.activeWar!.movesLeft[1]![0] = 5;

      final result = applyAction(
          s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed));
      final battle = result.events.where((e) => e.type == 'battle').toList();
      expect(battle, hasLength(1));
      // Report payload for the client's battle popup.
      expect(battle.single.payload['defenderSlot'], 2);
      expect(battle.single.payload['attackerDestroyed'], isA<bool>());
      expect(battle.single.payload['defenderDestroyed'], isA<bool>());
      final survivorsA =
          result.state.realm(1).troops.fold(0, (n, t) => n + t.men);
      final survivorsB =
          result.state.realm(2).troops.fold(0, (n, t) => n + t.men);
      expect(survivorsA + survivorsB, greaterThan(0));
      expect(result.state.realm(1).armySize,
          result.state.realm(1).towns.single.garrison);
    });

    test('mutual peace resolves the war; troops return to snapshots', () {
      // The AI defender wants peace once it is home AND the war is
      // decided (here: defender fields > 2× the attacker's units).
      var s = state.copy();
      for (final name in ['Zweite', 'Dritte']) {
        s = applyAction(
                s,
                RecruitTroops(slot: 2, men: 10, troopClass: 0, name: name),
                Rng(s.rngSeed))
            .state;
      }
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final troop = s.realm(1).troops.single;
      final homeX = troop.x;
      final homeY = troop.y;
      s = applyAction(
              s, WarPeaceWish(slot: 1, wantsPeace: true), Rng(s.rngSeed))
          .state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      expect(s.activeWar, isNull);
      expect(s.realm(1).troops.single.x, homeX);
      expect(s.realm(1).troops.single.y, homeY);
    });

    test('winter forcibly ends the war after round 20', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      for (var i = 0; i < 25 && s.activeWar != null; i++) {
        s.activeWar!.round = 21;
        final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
        s = result.state;
      }
      expect(s.activeWar, isNull);
      expect(s.events.any((e) => e.type == 'winterEndsWar'), isTrue);
    });

    test('plunder: once per round, never your own land', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final troop = s.realm(1).troops.single;
      final enemyTown = s.realm(2).towns.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      final treasuryBefore = s.realm(1).treasury;
      final enemyTreasury = s.realm(2).treasury;
      final result = applyAction(s,
          WarPlunder(slot: 1, x: enemyTown.x, y: enemyTown.y), Rng(s.rngSeed));
      s = result.state;
      expect(s.realm(1).treasury, greaterThanOrEqualTo(treasuryBefore));
      expect(s.realm(2).treasury, enemyTreasury,
          reason: 'town loot does NOT touch the victim treasury');
      expect(
        () => applyAction(
            s,
            WarPlunder(slot: 1, x: enemyTown.x, y: enemyTown.y),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Du hast diese Runde schon geplündert !',
      );
    });

    test('rules v5: battles bleed — a unit falls within a few engagements', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final a = s.realm(1).troops.single;
      final b = s.realm(2).troops.single;
      a.x = b.x - 1;
      a.y = b.y;

      // First encounter: both 50-man units take meaningful losses
      // (≥ ~15% on open ground; the capital tile defense softens b's).
      s.activeWar!.movesLeft[1]![0] = 5;
      var result = applyAction(
          s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed));
      s = result.state;
      final battle = result.events.singleWhere((e) => e.type == 'battle');
      expect(battle.payload['attackerLosses'], greaterThanOrEqualTo(2),
          reason: 'no more 0-loss skirmishes');
      expect(battle.payload['defenderLosses'], greaterThanOrEqualTo(1));

      // Repeated attacks: one side must be wiped out within ~6 fights.
      var encounters = 1;
      while (s.realm(1).troops.isNotEmpty &&
          s.realm(2).troops.isNotEmpty &&
          encounters < 12) {
        s.activeWar!.movesLeft[1]![0] = 5;
        result = applyAction(
            s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed));
        s = result.state;
        encounters += result.events.where((e) => e.type == 'battle').length;
      }
      expect(s.realm(1).troops.isEmpty || s.realm(2).troops.isEmpty, isTrue);
      expect(encounters, lessThanOrEqualTo(8),
          reason: 'a unit should fall after a few engagements, '
              'not a dozen skirmishes');
    });

    test('rules v5: TrainTroop retrains the class for 5 T/man + surcharge', () {
      final realm = state.realm(1);
      final treasury = realm.treasury;
      final men = realm.troops.single.men;
      var s = applyAction(
              state,
              TrainTroop(
                  slot: 1, unitIndex: 0, troopClass: TroopClass.kavallerie),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).troops.single.troopClass, TroopClass.kavallerie);
      expect(s.realm(1).treasury, treasury - (5 * men + 500));

      // Same class again → rejected; Söldner → rejected.
      expect(
        () => applyAction(
            s,
            TrainTroop(
                slot: 1, unitIndex: 0, troopClass: TroopClass.kavallerie),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      s = applyAction(
              s, HireSoeldner(slot: 1, men: 5, name: 'Garde'), Rng(s.rngSeed))
          .state;
      expect(
        () => applyAction(
            s,
            TrainTroop(
                slot: 1, unitIndex: 1, troopClass: TroopClass.artillerie),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Nur reguläre Truppen lassen sich ausbilden !',
      );
    });

    test('RenameTroop renames; forbidden at war (snapshots match by name)', () {
      var s = applyAction(
              state,
              RenameTroop(slot: 1, unitIndex: 0, name: ' Erste Garde '),
              Rng(state.rngSeed))
          .state;
      expect(s.realm(1).troops.single.name, 'Erste Garde');
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      expect(
        () => applyAction(
            s, RenameTroop(slot: 1, unitIndex: 0, name: 'X'), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Nicht mitten im Krieg !',
      );
    });

    test('rules v5: mutual peace is a white peace — no land, no payment', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // Attacker occupies the enemy town (war score >> 1000) while the
      // AI defender sits home → the defender wants peace next round.
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      final homeX = troop.x;
      final homeY = troop.y;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      expect(warScore(s, 1), greaterThanOrEqualTo(1000));
      final attackerTreasury = s.realm(1).treasury;
      final defenderTreasury = s.realm(2).treasury;

      s = applyAction(
              s, WarPeaceWish(slot: 1, wantsPeace: true), Rng(s.rngSeed))
          .state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar, isNull);
      expect(s.events.any((e) => e.type == 'peaceAgreed'), isTrue);
      expect(s.map.ownerAt(enemyTown.x, enemyTown.y), 2,
          reason: 'agreed peace must not move any tiles');
      expect(s.realm(2).towns, hasLength(1));
      expect(s.realm(1).treasury, attackerTreasury);
      expect(s.realm(2).treasury, defenderTreasury);
      expect(s.realm(1).troops.single.x, homeX);
      expect(s.realm(1).troops.single.y, homeY);
    });

    test(
        'a winter win opens the settlement — the winner picks '
        'tiles', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      final enemyTown = s.realm(2).towns.single;
      final troop = s.realm(1).troops.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      s.activeWar!.round = 21;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;

      expect(s.activeWar, isNotNull);
      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.winnerSlot, 1);
      expect(s.map.ownerAt(enemyTown.x, enemyTown.y), 2,
          reason: 'no auto-conversion — the winner chooses');

      // The bare border tile handed to slot 2 in setUp borders slot 1's
      // land: annexable for 100 claim points.
      final map = s.map;
      int? bx, by;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != 2 || map.buildingAt(x, y) != Building.none) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              bx = x;
              by = y;
              break outer;
            }
          }
        }
      }
      expect(bx, isNotNull);
      final claimBefore = s.activeWar!.remainingClaim;
      s = applyAction(
              s, SettlementAnnex(slot: 1, x: bx!, y: by!), Rng(s.rngSeed))
          .state;
      expect(s.map.ownerAt(bx, by), 1);
      expect(s.activeWar!.remainingClaim, claimBefore - 100);

      final loserTreasury = s.realm(2).treasury;
      final rest = s.activeWar!.remainingClaim;
      s = applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed)).state;
      expect(s.activeWar, isNull);
      expect(s.realm(2).treasury, loserTreasury - rest,
          reason: 'unspent claim converts 1:1 into Taler');
    });

    test('conquest transfer moves town objects and treasury shares', () {
      final winner = state.realm(1);
      final loser = state.realm(2);
      final town = loser.towns.single;
      final loserPop = loser.population;
      final winnerTreasury = winner.treasury;
      final events = <GameEvent>[];
      transferTile(state, town.x, town.y, 1, events);
      expect(loser.towns, isEmpty);
      expect(winner.towns, hasLength(2));
      expect(loser.population, loserPop - town.population);
      expect(winner.treasury, greaterThan(winnerTreasury),
          reason: 'treasury share moves with the town tile');
      expect(state.map.ownerAt(town.x, town.y), 1);
      expect(events.single.type, 'tileConquered');
    });
  });

  group('ruler capture opens the claim settlement', () {
    /// Declares war and parks slot 1's unit on slot 2's capital (the
    /// defender's unit is moved aside first).
    GameState marchOntoCapital() {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
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

    test('stepping onto the enemy capital does not end the war', () {
      final s = marchOntoCapital();
      expect(s.activeWar, isNotNull,
          reason: 'the capital must be HELD until round end');
      expect(s.activeWar!.phase, WarPhase.rounds);
      expect(s.events.any((e) => e.type == 'rulerCaptured'), isFalse);
      expect(capitalOccupier(s, s.activeWar!), 1);
    });

    test(
        'holding the capital through a full round captures the ruler and '
        'opens the claim settlement — no silent realm takeover', () {
      var s = marchOntoCapital();
      final loserRulerId = s.realm(2).rulerId;
      // First round end ARMS the capture; the second resolves it (the
      // defender gets one full round to retake the seat).
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(result.events.any((e) => e.type == 'rulerCaptured'), isTrue);
      expect(result.events.any((e) => e.type == 'warWon'), isTrue);
      expect(s.activeWar, isNotNull);
      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.winnerSlot, 1);
      expect(s.activeWar!.remainingClaim, greaterThanOrEqualTo(3000),
          reason: 'the claim includes the +3,000 capital bonus');
      expect(s.realm(2).rulerId, loserRulerId,
          reason: 'the loser keeps the realm — the winner SELECTS tiles');

      // The winner annexes a chosen loser tile against the claim: the
      // bare border tile handed to slot 2 in setUp costs 100.
      final map = s.map;
      int? bx, by;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != 2 || map.buildingAt(x, y) != Building.none) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              bx = x;
              by = y;
              break outer;
            }
          }
        }
      }
      expect(bx, isNotNull);
      final claimBefore = s.activeWar!.remainingClaim;
      s = applyAction(
              s, SettlementAnnex(slot: 1, x: bx!, y: by!), Rng(s.rngSeed))
          .state;
      expect(s.map.ownerAt(bx, by), 1);
      expect(s.activeWar!.remainingClaim, claimBefore - 100);

      // Finishing pays the unspent claim in Taler and ends the war.
      final rest = s.activeWar!.remainingClaim;
      final winnerTreasury = s.realm(1).treasury;
      s = applyAction(s, SettlementFinish(slot: 1), Rng(s.rngSeed)).state;
      expect(s.activeWar, isNull);
      expect(s.realm(1).treasury, winnerTreasury + rest);
    });

    test('a capital tile no longer owned by the enemy does not count', () {
      var s = marchOntoCapital();
      // The capital tile was conquered earlier — stale coordinates.
      s.map.owner[s.map.index(s.realm(2).capitalX, s.realm(2).capitalY)] = 1;
      expect(capitalOccupier(s, s.activeWar!), isNull);
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      expect(result.events.any((e) => e.type == 'rulerCaptured'), isFalse);
    });
  });

  group('ruler capture must be HELD through a full round (rules v11)', () {
    /// Declares war (latest rules) and parks slot 1's unit on slot 2's
    /// capital; the defender's unit is moved aside first.
    GameState marchOntoCapital() {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
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

    test('the first round end only ARMS the capture', () {
      var s = marchOntoCapital();
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(result.events.any((e) => e.type == 'capitalHeld'), isTrue);
      expect(result.events.any((e) => e.type == 'rulerCaptured'), isFalse,
          reason: 'the enemy gets a full round to retake the seat');
      expect(s.activeWar, isNotNull);
      expect(s.activeWar!.phase, WarPhase.rounds);
      expect(s.activeWar!.heldCapitalSlot, 1);
    });

    test('holding through the second round end resolves the capture', () {
      var s = marchOntoCapital();
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(result.events.any((e) => e.type == 'rulerCaptured'), isTrue);
      expect(result.events.any((e) => e.type == 'warWon'), isTrue);
      expect(s.activeWar!.phase, WarPhase.settlement);
      expect(s.activeWar!.winnerSlot, 1);
      expect(s.activeWar!.remainingClaim, greaterThanOrEqualTo(3000));
    });

    test('a dislodged occupier disarms the capture', () {
      var s = marchOntoCapital();
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      // The occupier is driven off (here: walks off) before the next
      // round end — the armed capture lapses.
      final troop = s.realm(1).troops.single;
      troop.x = s.realm(2).capitalX - 1;
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(result.events.any((e) => e.type == 'rulerCaptured'), isFalse);
      expect(s.activeWar!.heldCapitalSlot, isNull);
    });

    test('a troopless enemy cannot respond — capture resolves at once', () {
      var s = marchOntoCapital();
      s.realm(2).troops.clear();
      final result = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
      s = result.state;

      expect(result.events.any((e) => e.type == 'rulerCaptured'), isTrue);
      expect(s.activeWar!.phase, WarPhase.settlement);
    });

    test(
        'endWarRoundWithAi: an AI seizing the capital does not win in '
        'the same round end', () {
      // Slot 2 (AI) attacks slot 1 (human): the AI unit stands next to
      // the human capital and seizes it during its response movement.
      var s = applyAction(
              state, DeclareWar(slot: 2, targetSlot: 1), Rng(state.rngSeed))
          .state;
      final human = s.realm(1);
      human.troops.single.x = human.towns.single.x;
      human.troops.single.y = human.towns.single.y;
      final aiTroop = s.realm(2).troops.single;
      aiTroop.x = human.capitalX - 1;
      aiTroop.y = human.capitalY;
      s.activeWar!.movesLeft[2]![0] = 5;

      final events = <GameEvent>[];
      endWarRoundWithAi(s, Rng(s.rngSeed), events);

      expect(s.activeWar, isNotNull,
          reason: 'the human defender gets a full round to retake');
      expect(events.any((e) => e.type == 'rulerCaptured'), isFalse);
      if (capitalOccupier(s, s.activeWar!) == 2) {
        expect(s.activeWar!.heldCapitalSlot, 2,
            reason: 'the AI capture is armed, not resolved');
      }
    });
  });

  group('espionage (§13)', () {
    test('economy mission writes a fuzzed intel report', () {
      state.realm(2).treasury = 1000;
      state.realm(2).guardLevel = 0;
      final result = applyAction(
          state,
          SpyMission(
              slot: 1, targetSlot: 2, agents: 30, spyKind: SpyKind.economy),
          Rng(state.rngSeed));
      final spy = result.state.realm(1);
      expect(spy.treasury, state.realm(1).treasury - 30 * 200);
      expect(spy.intelReports, isNotEmpty);
      final report = spy.intelReports.single;
      expect(report.targetSlot, 2);
      expect(report.year, state.year);
      final treasury = report.values['treasury'];
      if (treasury != null) {
        expect(treasury, inInclusiveRange(900, 1100), reason: '±10% fuzz');
      }
    });

    test('agent count is capped at 30', () {
      expect(
        () => applyAction(
            state,
            SpyMission(
                slot: 1, targetSlot: 2, agents: 31, spyKind: SpyKind.economy),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('guards: 100 T each, capped at 50, dismissing free', () {
      var s = applyAction(
              state, AdjustGuards(slot: 1, delta: 50), Rng(state.rngSeed))
          .state;
      expect(s.realm(1).guardLevel, 50);
      expect(s.realm(1).treasury, state.realm(1).treasury - 5000);
      expect(
        () => applyAction(s, AdjustGuards(slot: 1, delta: 1), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Das ist keine Spionageabwehr, sondern eine Armee !!!',
      );
      s = applyAction(s, AdjustGuards(slot: 1, delta: -20), Rng(s.rngSeed))
          .state;
      expect(s.realm(1).guardLevel, 30);
    });

    test(
        'assassination resolves at the target\'s end-of-turn; failure '
        'names the sponsor', () {
      var found = false;
      for (var seed = 0; seed < 30 && !found; seed++) {
        var s = state.copy();
        s = applyAction(
                s,
                OrderAssassination(slot: 1, targetSlot: 2, agents: 30),
                Rng(s.rngSeed))
            .state;
        expect(s.assassinationOrders, hasLength(1));
        final victimId = s.realm(2).rulerId;
        // Advance until slot 2's end-of-turn ran (currentPlayer 1 → 2 → 3).
        s = completeTurn(s, Rng(seed)).state; // ends 1, begins 2
        s = completeTurn(s, Rng(seed + 1000)).state; // ends 2 → resolution
        expect(s.assassinationOrders, isEmpty);
        final killed = s.events.any((e) => e.type == 'assassination');
        final failed = s.events.any((e) => e.type == 'assassinationFailed');
        expect(killed || failed, isTrue);
        if (killed) {
          found = true;
          expect(s.realm(2).rulerId, isNot(victimId));
        } else {
          final reveal =
              s.events.firstWhere((e) => e.type == 'assassinationFailed');
          expect(reveal.payload['sponsorSlot'], 1,
              reason: 'the sponsor is publicly named');
          expect(reveal.visibility, EventVisibility.public);
        }
      }
      expect(found, isTrue,
          reason: '30 agents kill within 30 seeds (p≈30%+ each)');
    });
  });

  group('war bookkeeping fixes', () {
    test('no war against a slot your own ruler already holds', () {
      state.realm(2).rulerId = state.realm(1).rulerId;
      expect(
        () => applyAction(
            state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'ruler aliasing — merge instead',
      );
    });

    test('merge and disband are forbidden while at war', () {
      var s = applyAction(
              state,
              RecruitTroops(slot: 1, men: 10, troopClass: 0, name: 'Zweite'),
              Rng(state.rngSeed))
          .state;
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      expect(
        () =>
            applyAction(s, DisbandTroop(slot: 1, unitIndex: 0), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(
            s, MergeTroops(slot: 1, fromIndex: 0, toIndex: 1), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('human-vs-human wars are blocked (V1, online war clock pending)', () {
      state.dynasty(2).status = DynastyStatus.human;
      state.dynasty(2).humanPlayer = 1;
      expect(
        () => applyAction(
            state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'the V1 war UI can only seat one human side',
      );
    });

    test(
        'no recruiting, hiring, reinforcing or peacetime moves '
        'while at war', () {
      final s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      expect(
        () => applyAction(
            s,
            RecruitTroops(slot: 1, men: 5, troopClass: 0, name: 'Nachschub'),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(s, HireSoeldner(slot: 1, men: 5, name: 'Mietlinge'),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(
            s, ReinforceTroop(slot: 1, unitIndex: 0, men: 5), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      final capital = s.realm(1);
      expect(
        () => applyAction(
            s,
            MoveTroop(
                slot: 1,
                unitIndex: 0,
                x: capital.capitalX,
                y: capital.capitalY),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      // An uninvolved realm keeps its normal turn actions.
      final third = s.realms
          .firstWhere((r) => r.slot > 2 && !r.isVacant && r.towns.isNotEmpty)
          .slot;
      s.realm(third).treasury = 1000;
      expect(
          applyAction(
                  s,
                  RecruitTroops(
                      slot: third, men: 1, troopClass: 0, name: 'Wache'),
                  Rng(s.rngSeed))
              .state
              .realm(third)
              .troops,
          isNotEmpty);
    });

    test('plunder only hits the war opponent', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // Park the attacker's unit on a THIRD realm's town tile.
      final third = s.realms
          .firstWhere((r) => r.slot > 2 && !r.isVacant && r.towns.isNotEmpty);
      final troop = s.realm(1).troops.single;
      troop.x = third.towns.first.x;
      troop.y = third.towns.first.y;
      expect(
        () => applyAction(
            s, WarPlunder(slot: 1, x: troop.x, y: troop.y), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Das gehört nicht deinem Kriegsgegner !',
      );
      // The war opponent's town stays plunderable.
      final enemyTown = s.realm(2).towns.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      s = applyAction(
              s, WarPlunder(slot: 1, x: troop.x, y: troop.y), Rng(s.rngSeed))
          .state;
      final plunder = s.events.lastWhere((e) => e.type == 'plunder');
      // Result numbers for the client's plunder popup.
      expect(plunder.payload['loot'], isA<int>());
      expect(plunder.payload['killed'], isA<int>());
      expect(plunder.payload['destroyed'], isFalse);
    });

    test('bare land costs 100 in the claim settlement', () {
      expect(settlementTileValue(state, Building.none), 100);
      expect(settlementTileValue(state, Building.kornfeld), 100);
      expect(settlementTileValue(state, Building.markt), 2500);
    });

    test('settlement annex of bare land spends the claim', () {
      var s = applyAction(
              state, DeclareWar(slot: 1, targetSlot: 2), Rng(state.rngSeed))
          .state;
      // Force a limited victory for slot 1: its unit occupies the enemy
      // border tile (bare land, war score > 0 but below 40% of the
      // loser's territory value).
      final map = s.map;
      var bx = -1, by = -1;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != 2 || map.buildingAt(x, y) != Building.none) {
            continue;
          }
          for (final (dx, dy) in const [(-1, 0), (1, 0), (0, 1), (0, -1)]) {
            if (map.inBounds(x + dx, y + dy) &&
                map.ownerAt(x + dx, y + dy) == 1) {
              bx = x;
              by = y;
              break outer;
            }
          }
        }
      }
      expect(bx, greaterThanOrEqualTo(0),
          reason: 'setUp gave slot 2 a bare tile bordering slot 1');
      s.activeWar!
        ..phase = WarPhase.settlement
        ..winnerSlot = 1
        ..remainingClaim = 150;
      s = applyAction(s, SettlementAnnex(slot: 1, x: bx, y: by), Rng(s.rngSeed))
          .state;
      expect(s.activeWar!.remainingClaim, 50,
          reason: 'bare land costs 100 under rules v2');
      expect(s.map.ownerAt(bx, by), 1);
      expect(
        () => applyAction(
            s, SettlementAnnex(slot: 1, x: bx + 99, y: by), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test(
        'rules v2: conquering a town also cuts the loser\'s '
        'garrison-counted unit men', () {
      final loser = state.realm(2);
      final town = loser.towns.single;
      final garrison = town.garrison;
      expect(garrison, 50);
      final unitMenBefore = loser.troops.fold(0, (n, t) => n + t.men);
      transferTile(state, town.x, town.y, 1, <GameEvent>[]);
      final unitMenAfter = loser.troops.fold(0, (n, t) => n + t.men);
      expect(unitMenAfter, unitMenBefore - garrison);
      expect(loser.armySize, 0);
    });

    test('movesLeft stays aligned with the troop list when a unit dies', () {
      // Give the defender a 1-man sacrifice unit at INDEX 0 (in front of
      // its 50-man unit), so its death shifts every later index.
      var s = applyAction(
              state,
              RecruitTroops(slot: 2, men: 1, troopClass: 0, name: 'Opfer'),
              Rng(state.rngSeed))
          .state;
      final defenderTroops = s.realm(2).troops;
      defenderTroops.insert(0, defenderTroops.removeLast());
      expect(defenderTroops.first.name, 'Opfer');
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final attacker = s.realm(1).troops.first;
      final victim = s.realm(2).troops.firstWhere((t) => t.name == 'Opfer');
      // Place the victim on flat open ground next to the attacker (def 0
      // halves nothing away — 50 men kill 1 man on almost every roll).
      victim.x = attacker.x + 1;
      victim.y = attacker.y;
      final map = s.map;
      final index = map.index(victim.x, victim.y);
      map.terrain[index] = Terrain.ebene;
      map.building[index] = Building.none;
      map.owner[index] = World.niemand;
      s.activeWar!.movesLeft[1]![0] = 5;
      final survivorMoves = s.activeWar!.movesLeft[2]![1];

      var killed = false;
      for (var seed = 0; seed < 20 && !killed; seed++) {
        final trial = s.copy();
        final result = applyAction(
            trial, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(seed));
        if (result.state.realm(2).troops.length == 1) {
          killed = true;
          final war = result.state.activeWar!;
          expect(war.movesLeft[2], hasLength(1),
              reason: 'the dead unit\'s entry is dropped');
          expect(war.movesLeft[2]!.single, survivorMoves,
              reason: 'the surviving unit keeps its own budget after the '
                  'index shift');
        }
      }
      expect(killed, isTrue, reason: '1-man unit dies within 20 seeds');
    });
  });
}
