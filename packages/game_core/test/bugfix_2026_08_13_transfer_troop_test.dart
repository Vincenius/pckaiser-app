import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Regression tests for "Truppe übertragen" (`TransferTroop`, 2026-08-13)
/// and the war-plan revision (`WarPrepPlan`, 2026-08-09).
///
///  - a unit handed to an AI/free realm used to VANISH: it left the sender
///    at once but arrived through a `troopTransfer` pending decision, and
///    decisions exist for human dynasties only (the turn pipeline drops
///    every one addressed to an AI, and no AI driver answers them),
///  - the recipient of a garrison-counted unit never QUARTERED it, so
///    `Realm.armySize` (derived from the units) drifted away from the
///    per-town `garrison` fields it must mirror,
///  - a `WarPrepPlan` submitted while the `warPlan` prompt was still open
///    left that decision pending, so the preparation deadline defaulted the
///    side to the autopilot although it had just declared itself live.
void main() {
  GameState game({List<int> humanSlots = const [1]}) => startGame(
        newGame(GameSetup(
          humans: [
            for (var i = 0; i < humanSlots.length; i++)
              HumanPlayerSetup(
                  founderName: 'Mensch$i',
                  gender: 0,
                  countrySlot: humanSlots[i],
                  dorfName: 'Stadt$i'),
          ],
          reformationYear: 1020,
          ottomanYear: 1040,
          seed: 2026,
        )),
        Rng(7),
      ).state;

  int garrisonSum(Realm realm) =>
      realm.towns.fold(0, (a, town) => a + town.garrison);

  /// Adds a garrison-counted unit of [men] to [slot], quartered exactly as
  /// `applyRecruitTroops` would — the fixture must itself satisfy the
  /// `armySize == Σ town.garrison` invariant the tests check.
  Troop giveArmy(GameState state, int slot, int men) {
    final realm = state.realm(slot);
    for (final town in realm.towns) {
      town.population += men;
      town.troopCapacity += men;
    }
    realm.population = realm.towns.fold(0, (a, t) => a + t.population);
    realm.troopCapacity = realm.towns.fold(0, (a, t) => a + t.troopCapacity);
    quarterRecruits(realm, men, Rng(3));
    final troop = Troop(
      name: 'Heer$slot',
      men: men,
      troopClass: TroopClass.infanterie,
      quality: TroopQuality.regular,
      garrisonCounted: true,
      x: realm.capitalX,
      y: realm.capitalY,
    );
    realm.troops.add(troop);
    state.rebuildTroopMarkers();
    return troop;
  }

  group('transferring a unit to an AI realm', () {
    test('delivers it at the AI capital instead of deleting it', () {
      final state = game();
      state.year = 1010;
      giveArmy(state, 1, 20);
      final target = state.realms.firstWhere(
          (r) => r.slot != 1 && !r.isVacant && r.rulerId != null);
      expect(state.dynasty(target.slot).status, isNot(DynastyStatus.human),
          reason: 'fixture precondition: the recipient is AI-controlled');

      final next = applyAction(
              state,
              TransferTroop(slot: 1, unitIndex: 0, targetSlot: target.slot),
              Rng(state.rngSeed))
          .state;

      expect(next.realm(1).troops, isEmpty);
      expect(next.realm(target.slot).troops.single.men, 20,
          reason: 'the unit arrives — it must not fall into a decision no '
              'AI will ever answer');
      expect(next.pendingDecisions.where((d) => d.type == 'troopTransfer'),
          isEmpty);
      final received = next.realm(target.slot).troops.single;
      expect((received.x, received.y),
          (next.realm(target.slot).capitalX, next.realm(target.slot).capitalY));
    });

    test('leaves both realms with a consistent garrison', () {
      final state = game();
      state.year = 1010;
      giveArmy(state, 1, 20);
      final target = state.realms
          .firstWhere((r) => r.slot != 1 && !r.isVacant && r.rulerId != null);

      final next = applyAction(
              state,
              TransferTroop(slot: 1, unitIndex: 0, targetSlot: target.slot),
              Rng(state.rngSeed))
          .state;

      expect(next.realm(1).armySize, garrisonSum(next.realm(1)));
      final recipient = next.realm(target.slot);
      expect(recipient.armySize, garrisonSum(recipient));
      expect(recipient.armySize, lessThanOrEqualTo(recipient.troopCapacity));
    });
  });

  group('transferring a unit to a human realm', () {
    PendingDecision transferOf(GameState state) => state.pendingDecisions
        .singleWhere((d) => d.type == 'troopTransfer');

    test('quarters the received unit so armySize matches the garrisons', () {
      final state = game(humanSlots: const [1, 2]);
      state.year = 1010;
      giveArmy(state, 1, 20);
      // Capacity headroom for the gift in the recipient's towns.
      final recipientRealm = state.realm(2);
      for (final town in recipientRealm.towns) {
        town.population += 50;
        town.troopCapacity += 50;
      }
      recipientRealm.population =
          recipientRealm.towns.fold(0, (a, t) => a + t.population);
      recipientRealm.troopCapacity =
          recipientRealm.towns.fold(0, (a, t) => a + t.troopCapacity);

      final sent = applyAction(
              state,
              TransferTroop(slot: 1, unitIndex: 0, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      expect(sent.realm(1).armySize, garrisonSum(sent.realm(1)));

      final next = applyAction(
              sent,
              ResolveDecision(
                  slot: 2, decisionId: transferOf(sent).id, choice: const {}),
              Rng(sent.rngSeed))
          .state;

      final recipient = next.realm(2);
      expect(recipient.troops.singleWhere((t) => t.name == 'Heer1').men, 20);
      expect(recipient.armySize, garrisonSum(recipient),
          reason: 'a garrison-counted unit must occupy quarters in its new '
              'realm, or armySize drifts from the town garrisons forever');
    });

    test('cuts the men the recipient cannot house (§8.3)', () {
      final state = game(humanSlots: const [1, 2]);
      state.year = 1010;
      giveArmy(state, 1, 20);
      // The recipient's towns are full: no quarters for the gift at all.
      final recipientRealm = state.realm(2);
      for (final town in recipientRealm.towns) {
        town.troopCapacity = town.garrison;
      }
      recipientRealm.troopCapacity =
          recipientRealm.towns.fold(0, (a, t) => a + t.troopCapacity);

      final sent = applyAction(
              state,
              TransferTroop(slot: 1, unitIndex: 0, targetSlot: 2),
              Rng(state.rngSeed))
          .state;
      final next = applyAction(
              sent,
              ResolveDecision(
                  slot: 2, decisionId: transferOf(sent).id, choice: const {}),
              Rng(sent.rngSeed))
          .state;

      final recipient = next.realm(2);
      expect(recipient.troops, isEmpty);
      expect(recipient.armySize, garrisonSum(recipient));
      expect(
          next.events.where((e) => e.type == 'troopsReceived').single
              .payload['men'],
          0,
          reason: 'the report states what actually arrived, not what was sent');
    });
  });

  test('a realm at war takes no reinforcements from a bystander', () {
    final state = game(humanSlots: const [1]);
    state.year = 1010;
    giveArmy(state, 1, 20);
    final belligerent = state.realms
        .firstWhere((r) => r.slot != 1 && !r.isVacant && r.rulerId != null);
    final other = state.realms.firstWhere((r) =>
        r.slot != 1 && r.slot != belligerent.slot && !r.isVacant &&
        r.rulerId != null);
    state.activeWar =
        ActiveWar(attackerSlot: belligerent.slot, defenderSlot: other.slot);

    expect(
        () => applyAction(
            state,
            TransferTroop(slot: 1, unitIndex: 0, targetSlot: belligerent.slot),
            Rng(state.rngSeed)),
        throwsA(isA<ActionException>().having(
            (e) => e.message, 'message', coreMessage('notDuringWar'))));
  });

  test('a plan revision answers a still-open warPlan prompt', () {
    final state = game(humanSlots: const [1, 2]);
    state.year = 1010;
    giveArmy(state, 1, 100);
    giveArmy(state, 2, 100);
    final war = startWar(state, 1, 2, Rng(1));
    expect(
        state.pendingDecisions
            .where((d) => d.type == 'warPlan' && d.decidingSlot == 2),
        isNotEmpty);

    // The defender revises straight to LIVE command without going through
    // the prompt. The prompt must be consumed — otherwise the preparation
    // deadline would file them under `autoSlots` as an absent player.
    applyActionInPlace(
        state, WarPrepPlan(slot: 2, auto: false, slots: const [1000]), Rng(1));
    expect(
        state.pendingDecisions
            .where((d) => d.type == 'warPlan' && d.decidingSlot == 2),
        isEmpty);

    applyActionInPlace(
        state, WarPrepPlan(slot: 1, auto: false, slots: const [1000]), Rng(1));
    resolveWarPreparation(state, Rng(1), <GameEvent>[], force: true);
    expect(war.autoSlots, isEmpty,
        reason: 'both sides declared themselves live before the deadline');
    expect(war.phase, WarPhase.rounds);
  });
}
