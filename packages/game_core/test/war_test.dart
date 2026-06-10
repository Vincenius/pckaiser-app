import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  late GameState state;

  setUp(() {
    state = startGame(
        newGame(GameSetup(
          humans: [
            HumanPlayerSetup(
                founderName: 'Anna', gender: 1, countrySlot: 1, dorfName: 'A'),
            HumanPlayerSetup(
                founderName: 'Berta', gender: 1, countrySlot: 2, dorfName: 'B'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 2026,
        )),
        Rng(7)).state;
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
          Rng(state.rngSeed)).state;
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
            RecruitTroops(
                slot: 1, men: 151, troopClass: 0, name: 'Zuviel'),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'capacity 200, garrison 50',
      );
    });

    test('cavalry surcharge, Söldner outside the garrison', () {
      var s = applyAction(
          state,
          RecruitTroops(
              slot: 1, men: 10, troopClass: TroopClass.kavallerie,
              name: 'Reiter'),
          Rng(state.rngSeed)).state;
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
          Rng(state.rngSeed)).state;
      s = applyAction(
              s, MergeTroops(slot: 1, fromIndex: 1, toIndex: 0), Rng(1))
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
          .firstWhere((r) =>
              r.slot != 1 && !r.isVacant && !neighbors.contains(r.slot))
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
        () => applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Kriege sind erst ab dem Jahr 1010 erlaubt !',
      );
      state.year = 1010;
      state.realm(1).warThisYear = true;
      expect(
        () => applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      state.realm(1).warThisYear = false;
      final s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      expect(s.activeWar, isNotNull);
      expect(s.activeWar!.attackerSlot, 1);
      expect(s.realm(1).warThisYear, isTrue);
      expect(s.activeWar!.snapshots[1], hasLength(1));
    });

    test('marching onto the enemy capital captures the ruler and takes '
        'the realm', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      final enemy = s.realm(2);
      // The defender's unit must not block the capital tile.
      enemy.troops.single.x = enemy.towns.single.x;
      enemy.troops.single.y = enemy.towns.single.y;
      final troop = s.realm(1).troops.single;
      // Teleport next to the enemy capital for the test, then step on it.
      troop.x = enemy.capitalX - 1;
      troop.y = enemy.capitalY;
      s.activeWar!.movesLeft[1]![0] = 5;
      final loserRulerId = enemy.rulerId;

      final result = applyAction(
          s, WarMove(slot: 1, unitIndex: 0, dx: 1, dy: 0), Rng(s.rngSeed));
      s = result.state;

      expect(s.activeWar, isNull, reason: 'war ends on ruler capture');
      expect(s.realm(2).rulerId, s.realm(1).rulerId,
          reason: 'slot pointer overwritten');
      // D1 decision: control follows the new ruler — the captured slot is
      // now dispatched to the captor's controller.
      expect(s.dynasty(2).status, s.dynasty(1).status);
      expect(s.dynasty(2).humanPlayer, s.dynasty(1).humanPlayer);
      expect(result.events.any((e) => e.type == 'rulerCaptured'), isTrue);
      // Both rulers female, different religion? Same religion (katholisch),
      // marriage-incompatible (same gender) → loser was Kurfürstin? Human
      // victor → coercion decision only if an option applied.
      expect(loserRulerId, isNotNull);
    });

    test('combat applies the defense-scaled losses and never both wipe',
        () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
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
      final battle =
          result.events.where((e) => e.type == 'battle').toList();
      expect(battle, hasLength(1));
      final survivorsA = result.state.realm(1).troops.fold(0, (n, t) => n + t.men);
      final survivorsB = result.state.realm(2).troops.fold(0, (n, t) => n + t.men);
      expect(survivorsA + survivorsB, greaterThan(0));
      expect(result.state.realm(1).armySize,
          result.state.realm(1).towns.single.garrison);
    });

    test('mutual peace resolves the war; troops return to snapshots', () {
      // The AI defender wants peace once it is home AND the war is
      // decided (here: defender fields > 2× the attacker's units).
      var s = state.copy();
      for (final name in ['Zweite', 'Dritte']) {
        s = applyAction(s,
                RecruitTroops(slot: 2, men: 10, troopClass: 0, name: name),
                Rng(s.rngSeed))
            .state;
      }
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final troop = s.realm(1).troops.single;
      final homeX = troop.x;
      final homeY = troop.y;
      s = applyAction(s, WarPeaceWish(slot: 1, wantsPeace: true),
              Rng(s.rngSeed))
          .state;
      s = applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed)).state;
      expect(s.activeWar, isNull);
      expect(s.realm(1).troops.single.x, homeX);
      expect(s.realm(1).troops.single.y, homeY);
    });

    test('winter forcibly ends the war after round 20', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      for (var i = 0; i < 25 && s.activeWar != null; i++) {
        s.activeWar!.round = 21;
        final result =
            applyAction(s, WarEndRound(slot: 1), Rng(s.rngSeed));
        s = result.state;
      }
      expect(s.activeWar, isNull);
      expect(s.events.any((e) => e.type == 'winterEndsWar'), isTrue);
    });

    test('plunder: once per round, never your own land', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      final troop = s.realm(1).troops.single;
      final enemyTown = s.realm(2).towns.single;
      troop.x = enemyTown.x;
      troop.y = enemyTown.y;
      final treasuryBefore = s.realm(1).treasury;
      final enemyTreasury = s.realm(2).treasury;
      final result = applyAction(
          s,
          WarPlunder(slot: 1, x: enemyTown.x, y: enemyTown.y),
          Rng(s.rngSeed));
      s = result.state;
      expect(s.realm(1).treasury, greaterThanOrEqualTo(treasuryBefore));
      expect(s.realm(2).treasury, enemyTreasury,
          reason: 'town loot does NOT touch the victim treasury');
      expect(
        () => applyAction(s, WarPlunder(slot: 1, x: enemyTown.x, y: enemyTown.y),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'Du hast diese Runde schon geplündert !',
      );
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
      var s = applyAction(state, AdjustGuards(slot: 1, delta: 50),
              Rng(state.rngSeed))
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

    test('assassination resolves at the target\'s end-of-turn; failure '
        'names the sponsor', () {
      var found = false;
      for (var seed = 0; seed < 30 && !found; seed++) {
        var s = state.copy();
        s = applyAction(
                s, OrderAssassination(slot: 1, targetSlot: 2, agents: 30),
                Rng(s.rngSeed))
            .state;
        expect(s.assassinationOrders, hasLength(1));
        final victimId = s.realm(2).rulerId;
        // Advance until slot 2's end-of-turn ran (currentPlayer 1 → 2 → 3).
        s = completeTurn(s, Rng(seed)).state; // ends 1, begins 2
        s = completeTurn(s, Rng(seed + 1000)).state; // ends 2 → resolution
        expect(s.assassinationOrders, isEmpty);
        final killed = s.events.any((e) => e.type == 'assassination');
        final failed =
            s.events.any((e) => e.type == 'assassinationFailed');
        expect(killed || failed, isTrue);
        if (killed) {
          found = true;
          expect(s.realm(2).rulerId, isNot(victimId));
        } else {
          final reveal = s.events
              .firstWhere((e) => e.type == 'assassinationFailed');
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
        () => applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'ruler aliasing — merge instead',
      );
    });

    test('merge and disband are forbidden while at war', () {
      var s = applyAction(state,
              RecruitTroops(slot: 1, men: 10, troopClass: 0, name: 'Zweite'),
              Rng(state.rngSeed))
          .state;
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      expect(
        () => applyAction(
            s, DisbandTroop(slot: 1, unitIndex: 0), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(
            s, MergeTroops(slot: 1, fromIndex: 0, toIndex: 1), Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('human-vs-human wars are blocked (V1, online war clock pending)',
        () {
      state.dynasty(2).status = DynastyStatus.human;
      state.dynasty(2).humanPlayer = 1;
      expect(
        () => applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>()),
        reason: 'the V1 war UI can only seat one human side',
      );
    });

    test('rules v2: no recruiting, hiring, reinforcing or peacetime moves '
        'while at war', () {
      expect(state.rulesVersion, greaterThanOrEqualTo(2));
      final s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      expect(
        () => applyAction(s,
            RecruitTroops(slot: 1, men: 5, troopClass: 0, name: 'Nachschub'),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(
            s, HireSoeldner(slot: 1, men: 5, name: 'Mietlinge'),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
      expect(
        () => applyAction(s,
            ReinforceTroop(slot: 1, unitIndex: 0, men: 5), Rng(s.rngSeed)),
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

    test('rules v2: plunder only hits the war opponent', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      // Park the attacker's unit on a THIRD realm's town tile.
      final third = s.realms.firstWhere(
          (r) => r.slot > 2 && !r.isVacant && r.towns.isNotEmpty);
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
      expect(s.events.any((e) => e.type == 'plunder'), isTrue);
    });

    test('rules v2: bare land costs 100 in the claim settlement, '
        'v1 keeps it free', () {
      expect(settlementTileValue(state, Building.none), 100);
      expect(settlementTileValue(state, Building.markt), 2500);
      final v1 = GameState.fromJson(state.toJson()..['rulesVersion'] = 1);
      expect(settlementTileValue(v1, Building.none), 0);
      expect(settlementTileValue(v1, Building.kornfeld), 100);
    });

    test('rules v2: settlement annex of bare land spends the claim', () {
      var s = applyAction(state, DeclareWar(slot: 1, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      // Force a limited victory for slot 1: its unit occupies the enemy
      // border tile (bare land, war score > 0 but below 40% of the
      // loser's territory value).
      final map = s.map;
      var bx = -1, by = -1;
      outer:
      for (var y = 0; y < map.height; y++) {
        for (var x = 0; x < map.width; x++) {
          if (map.ownerAt(x, y) != 2 ||
              map.buildingAt(x, y) != Building.none) {
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
      s = applyAction(
              s, SettlementAnnex(slot: 1, x: bx, y: by), Rng(s.rngSeed))
          .state;
      expect(s.activeWar!.remainingClaim, 50,
          reason: 'bare land costs 100 under rules v2');
      expect(s.map.ownerAt(bx, by), 1);
      expect(
        () => applyAction(s, SettlementAnnex(slot: 1, x: bx + 99, y: by),
            Rng(s.rngSeed)),
        throwsA(isA<ActionException>()),
      );
    });

    test('rules v2: conquering a town also cuts the loser\'s '
        'garrison-counted unit men', () {
      final loser = state.realm(2);
      final town = loser.towns.single;
      final garrison = town.garrison;
      expect(garrison, 50);
      final unitMenBefore =
          loser.troops.fold(0, (n, t) => n + t.men);
      transferTile(state, town.x, town.y, 1, <GameEvent>[]);
      final unitMenAfter = loser.troops.fold(0, (n, t) => n + t.men);
      expect(unitMenAfter, unitMenBefore - garrison);
      expect(loser.armySize, 0);
    });

    test('movesLeft stays aligned with the troop list when a unit dies',
        () {
      // Give the defender a 1-man sacrifice unit at INDEX 0 (in front of
      // its 50-man unit), so its death shifts every later index.
      var s = applyAction(state,
              RecruitTroops(slot: 2, men: 1, troopClass: 0, name: 'Opfer'),
              Rng(state.rngSeed))
          .state;
      final defenderTroops = s.realm(2).troops;
      defenderTroops.insert(0, defenderTroops.removeLast());
      expect(defenderTroops.first.name, 'Opfer');
      s = applyAction(s, DeclareWar(slot: 1, targetSlot: 2), Rng(s.rngSeed))
          .state;
      final attacker = s.realm(1).troops.first;
      final victim =
          s.realm(2).troops.firstWhere((t) => t.name == 'Opfer');
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
