import 'package:game_core/game_core.dart';

/// Usage: `dart tool/sim_report.dart [leicht|mittel|schwer]` — the AI
/// difficulty the 200-year world runs on (default mittel), so balance
/// changes to the leicht/schwer scripts get long-run coverage too.
void main(List<String> args) {
  final difficulty = AiDifficulty.fromName(args.isEmpty ? null : args.first);
  print('ai difficulty: ${difficulty.name}');

  // `state.events` is capped (maxRetainedEvents), so tally incrementally
  // from the TurnResults instead of the final state.
  final counts = <String, int>{};
  void tally(Iterable<GameEvent> events) {
    for (final e in events) {
      counts[e.type] = (counts[e.type] ?? 0) + 1;
    }
  }

  final start = startGame(
      newGame(GameSetup(
        humans: const [],
        reformationYear: 1020,
        ottomanYear: 1040,
        aiDifficulty: difficulty,
        seed: 777,
      )),
      Rng(777));
  var state = start.state;
  tally(start.events);
  var total = start.events.length;
  var safety = 0;
  while (state.year < 1200 && safety++ < 8000) {
    final slot = state.currentPlayer;
    if (!state.realm(slot).isVacant &&
        state.dynasty(slot).status == DynastyStatus.ai) {
      final result = runAiTurn(state, slot, Rng(state.rngSeed));
      state = result.state;
      tally(result.events);
      total += result.events.length;
    }
    final result = completeTurn(state, Rng(state.rngSeed));
    state = result.state;
    tally(result.events);
    total += result.events.length;
    if (result.events.any((e) => e.type == 'gameWon')) break;
  }
  print('final year: ${state.year}, events: $total '
      '(retained in state: ${state.events.length}, '
      'pruned: ${state.prunedEventCount})');
  final interesting = [
    'warDeclared',
    'battle',
    'rulerCaptured',
    'warWon',
    'tileConquered',
    'plunder',
    'assassination',
    'disease',
    'earthquake',
    'reformation',
    'ottomanInvasion',
    'crowned',
    'bankruptcy',
    'internalStrife',
    'merchantFounder',
    'wedding',
    'birth',
    'succession',
    'gameWon',
    'townPromoted',
    'realmsMerged'
  ];
  for (final k in interesting) {
    print('  $k: ${counts[k] ?? 0}');
  }
  final living = state.realms.where((r) => !r.isVacant).length;
  print('living realms: $living');
}
