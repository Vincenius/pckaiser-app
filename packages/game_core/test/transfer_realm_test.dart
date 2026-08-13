import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// "Reich übertragen" [DESIGNED, deviation]: a ruler may voluntarily hand
/// their entire realm to a FOREIGN ruler — the complement of the §6.2
/// same-control merge. The seat is vacated, the dynasty's court moves to
/// the target, and the abdicating ruler forfeits Kaiser crown and
/// Kurfürst seat unless they still rule another realm.
void main() {
  GameState freshGame() {
    final state = startGame(
      newGame(GameSetup(
        humans: [
          HumanPlayerSetup(
              founderName: 'Otto', gender: 0, countrySlot: 1, dorfName: 'A'),
        ],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 2026,
      )),
      Rng(7),
    ).state;
    state.year = 1010;
    return state;
  }

  test('transferableSlots lists foreign realms, never own seats', () {
    final state = freshGame();
    final targets = transferableSlots(state, 1);
    expect(targets, isNot(contains(1)), reason: 'never the own seat');
    expect(targets, isNotEmpty, reason: 'foreign AI realms are valid targets');
    for (final slot in mergeableSlots(state, 1)) {
      expect(targets, isNot(contains(slot)),
          reason: 'own-controlled seats consolidate via merge, not transfer');
    }
  });

  test('transferring hands everything over and vacates the seat', () {
    final state = freshGame();
    final target = transferableSlots(state, 1).first;
    final source = state.realm(1);
    final targetBefore = state.realm(target);
    final expectedTreasury = targetBefore.treasury + source.treasury;
    final expectedTiles = [
      for (var b = 0; b < source.tileCount.length; b++)
        targetBefore.tileCount[b] + source.tileCount[b],
    ];

    final result = applyAction(
        state, TransferRealm(slot: 1, targetSlot: target), Rng(state.rngSeed));
    final next = result.state;

    expect(next.realm(target).treasury, expectedTreasury);
    expect(next.realm(target).tileCount, expectedTiles);
    expect(next.realm(1).rulerId, isNull, reason: 'the source seat is vacated');
    expect(next.realm(1).tileCount.fold<int>(0, (a, b) => a + b), 0);
    expect(next.dynasty(1).status, DynastyStatus.ai,
        reason: 'a vacated slot is no longer a human seat');
    expect(next.dynasty(1).humanPlayer, isNull);

    final event =
        result.events.singleWhere((e) => e.type == 'realmTransferred');
    expect(event.slot, target);
    expect(event.payload['sourceSlot'], 1);
    expect(event.payload['human'], isTrue);
    expect(result.events.where((e) => e.type == 'realmsMerged'), isEmpty,
        reason: 'a transfer reports as realmTransferred, not as a merge');
  });

  test('the abdicating ruler forfeits Kaiser crown and Kurfürst seat', () {
    final state = freshGame();
    final rulerId = state.realm(1).rulerId!;
    state.kaiserId = rulerId;
    // The start setup may already have elected him — never a duplicate.
    if (!state.kurfuerstenIds.contains(rulerId)) {
      state.kurfuerstenIds.add(rulerId);
    }
    final target = transferableSlots(state, 1).first;

    final result = applyAction(
        state, TransferRealm(slot: 1, targetSlot: target), Rng(state.rngSeed));
    final next = result.state;

    expect(next.kaiserId, isNull, reason: 'the crown is forfeit');
    expect(next.kurfuerstenIds, isNot(contains(rulerId)));
    expect(result.events.any((e) => e.type == 'forcedAbdication'), isTrue);
    expect(result.events.any((e) => e.type == 'kurfuerstStripped'), isTrue);
  });

  test('emits gameWon when the last rival transfers their realm', () {
    final state = freshGame();
    final target = transferableSlots(state, 1).first;

    // Leave only the transferring human and the foreign recipient alive.
    for (final realm in state.realms) {
      if (realm.slot != 1 && realm.slot != target) {
        realm.rulerId = null;
        realm.tileCount.fillRange(0, realm.tileCount.length, 0);
      }
    }

    final result = applyAction(
      state,
      TransferRealm(slot: 1, targetSlot: target),
      Rng(state.rngSeed),
    );

    final won = result.events.where((event) => event.type == 'gameWon');
    expect(won, hasLength(1));
    expect(won.single.slot, target,
        reason: 'the receiving player is the sole remaining ruler');
  });

  test('refuses own-controlled and invalid targets', () {
    final state = freshGame();
    expect(
      () => applyAction(
          state, TransferRealm(slot: 1, targetSlot: 1), Rng(state.rngSeed)),
      throwsA(isA<ActionException>()),
    );
  });
}
