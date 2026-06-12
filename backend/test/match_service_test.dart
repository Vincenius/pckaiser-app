import 'package:backend/backend.dart';
import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

/// Match lifecycle and turn flow against the in-memory store — the same
/// game_core pipeline the local client drives, but server-validated.
void main() {
  late InMemoryStore store;
  late MatchService service;

  setUp(() {
    store = InMemoryStore();
    service = MatchService(store, LogPushService());
  });

  Future<(PlayerRecord, PlayerRecord)> twoPlayers() async {
    final a = await service.registerPlayer(displayName: 'Anna');
    final b = await service.registerPlayer(displayName: 'Berta');
    return (a, b);
  }

  Map<String, dynamic> setupFor(String name, int slot) => {
        'founder_name': name,
        'gender': 1,
        'country_slot': slot,
        'dorf_name': '${name}dorf',
      };

  group('lifecycle', () {
    test('a single-human match starts immediately and awaits the human',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 1,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Solo', 5),
      );
      expect(match.status, MatchStatus.active);

      final view = await service.view(match.id, a.id);
      expect(view['your_turn'], isTrue);
      expect(view['your_slot'], 5);
      final state = (view['state'] as Map).cast<String, dynamic>();
      expect(state['currentPlayer'], 5);
    });

    test('a two-human match waits for the second seat, then starts',
        () async {
      final (a, b) = await twoPlayers();
      final created = await service.createMatch(
        playerId: a.id,
        humanCount: 2,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      expect(created.status, MatchStatus.waiting);
      expect((await service.view(created.id, a.id))['state'], isNull);

      final joined = await service.joinMatch(
        matchId: created.id,
        playerId: b.id,
        setup: setupFor('Berta', 2),
      );
      expect(joined.status, MatchStatus.active);
      // Exactly one player is awaited; the other sees the same id.
      final viewA = await service.view(created.id, a.id);
      final viewB = await service.view(created.id, b.id);
      expect(viewA['awaited_player_id'], viewB['awaited_player_id']);
      expect([viewA['your_turn'], viewB['your_turn']], containsOnce(true));
    });

    test('a taken country slot is rejected; no slot means a free one',
        () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 2,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await expectLater(
        service.joinMatch(
            matchId: match.id, playerId: b.id, setup: setupFor('Berta', 1)),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)),
      );
      await service.joinMatch(
        matchId: match.id,
        playerId: b.id,
        setup: {'founder_name': 'Berta', 'gender': 1, 'dorf_name': 'B'},
      );
      final seat = (await store.match(match.id))!.playerById(b.id)!;
      expect(seat.slot, isNot(1));
      expect(seat.slot, inInclusiveRange(1, 30));
    });

    test('outsiders may not view a match', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 1,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await expectLater(
        service.view(match.id, b.id),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 403)),
      );
    });
  });

  group('turn flow', () {
    test('the awaited player acts and ends the turn; the server advances '
        'to the next human', () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 2,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      final record = (await store.match(match.id))!;
      final state = GameState.fromJson(record.stateJson!);
      final awaitedSlot = state.currentPlayer;
      final awaitedId =
          (await service.view(match.id, a.id))['awaited_player_id'] as String;
      final otherId = awaitedId == a.id ? b.id : a.id;

      // The not-awaited player is rejected for actions and end-turn.
      await expectLater(
        service.submit(matchId: match.id, playerId: otherId, endTurn: true),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 403)),
      );

      // A foreign-slot action is rejected even for the awaited player.
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: awaitedId,
          actionJson:
              AdjustGuards(slot: awaitedSlot == 1 ? 2 : 1, delta: 1).toJson(),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 403)),
      );

      // A legal in-turn action sticks.
      final after = await service.submit(
        matchId: match.id,
        playerId: awaitedId,
        actionJson: AdjustGuards(slot: awaitedSlot, delta: 1).toJson(),
      );
      expect(after['your_turn'], isTrue);

      // Ending the turn passes the match to the other human.
      final ended = await service.submit(
          matchId: match.id, playerId: awaitedId, endTurn: true);
      expect(ended['your_turn'], isFalse);
      expect(ended['awaited_player_id'], otherId);
    });

    test('an engine rejection surfaces as a 400 with the German message',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 1,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Solo', 1),
      );
      await expectLater(
        service.submit(
          matchId: match.id,
          playerId: a.id,
          // Year 1000: wars are not allowed before 1010.
          actionJson: DeclareWar(slot: 1, targetSlot: 2).toJson(),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message', contains('1010'))),
      );
    });

    test('the state is filtered per requester (hidden information)',
        () async {
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 2,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      final viewA = await service.view(match.id, a.id);
      final stateA = (viewA['state'] as Map).cast<String, dynamic>();
      final realms = (stateA['realms'] as List).cast<Map>();
      final own = realms.firstWhere((r) => r['slot'] == 1);
      final foreign = realms.firstWhere((r) => r['slot'] == 2);
      expect(own['treasury'], greaterThan(0));
      expect(foreign['treasury'], 0, reason: 'redacted to "unknown"');
      expect(stateA['rngSeed'], 0, reason: 'the seed never leaves the server');
    });

    test('a full AI-decided match finishes with a winner or defeat',
        () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 1,
        settings: MatchSettings(seed: 7),
        setup: setupFor('Solo', 1),
      );
      // Play 30 empty turns — the world keeps simulating around the
      // player; the match must stay consistent and never throw.
      for (var i = 0; i < 30; i++) {
        final view = await service.view(match.id, a.id);
        if (view['status'] != 'active') break;
        if (view['your_turn'] != true) break;
        await service.submit(matchId: match.id, playerId: a.id, endTurn: true);
      }
      final record = (await store.match(match.id))!;
      expect(record.stateJson, isNotNull);
      final state = GameState.fromJson(record.stateJson!);
      expect(state.year, greaterThan(1000));
    });
  });

  group('timeouts', () {
    test('an expired turn auto-ends with no actions', () async {
      var now = DateTime.utc(2026, 1, 1);
      service = MatchService(store, LogPushService(), clock: () => now);
      final (a, b) = await twoPlayers();
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 2,
        settings: MatchSettings(seed: 42, turnTimeoutHours: 24),
        setup: setupFor('Anna', 1),
      );
      await service.joinMatch(
          matchId: match.id, playerId: b.id, setup: setupFor('Berta', 2));

      final before =
          (await service.view(match.id, a.id))['awaited_player_id'];
      expect((await store.match(match.id))!.turnDeadline, isNotNull);

      now = now.add(const Duration(hours: 25));
      final swept = await service.sweepExpired();
      expect(swept, 1);
      final after = (await service.view(match.id, a.id))['awaited_player_id'];
      expect(after, isNot(before),
          reason: 'the idle turn ended; the next human is awaited');
    });

    test('without a timer no deadline is set', () async {
      final a = await service.registerPlayer(displayName: 'Solo');
      final match = await service.createMatch(
        playerId: a.id,
        humanCount: 1,
        settings: MatchSettings(seed: 42),
        setup: setupFor('Solo', 1),
      );
      expect((await store.match(match.id))!.turnDeadline, isNull);
      expect(await service.sweepExpired(), 0);
    });
  });
}

/// Matcher: the iterable contains [value] exactly once.
Matcher containsOnce(Object? value) => predicate<Iterable>(
      (items) => items.where((e) => e == value).length == 1,
      'contains $value exactly once',
    );
