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

  // Sample every living realm's own regular units once per game-year, so the
  // troop-composition report reflects the WHOLE run (many realms alive), not
  // just the consolidated end state (a handful of survivors).
  final units = <(int men, int quality, int cls)>[];
  var lastSampledYear = -1;
  void sampleTroops() {
    if (state.year == lastSampledYear) return;
    lastSampledYear = state.year;
    for (final r in state.realms) {
      if (r.isVacant) continue;
      for (final t in r.troops) {
        if (!t.garrisonCounted) continue; // own regulars only
        units.add((t.men, t.quality, t.troopClass));
      }
    }
  }

  sampleTroops();
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
    sampleTroops();
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

  // Troop composition sampled yearly across all living realms — the balance
  // signal: does the AI field cheap hordes (many men, quality 1), expensive
  // elites (few men, high quality), or a healthy mix of both?
  print('\n--- troop composition (${units.length} yearly unit samples) ---');
  if (units.isNotEmpty) {
    double strengthOf((int men, int quality, int cls) u) =>
        u.$1 * (3 * u.$3 + u.$2) / 10;
    final totalMen = units.fold(0, (a, u) => a + u.$1);
    final totalStr = units.fold(0.0, (a, u) => a + strengthOf(u));
    final avgMen = totalMen / units.length;
    final avgQ = units.fold(0, (a, u) => a + u.$2) / units.length;
    final maxQ = units.fold(0, (a, u) => u.$2 > a ? u.$2 : a);
    final maxMen = units.fold(0, (a, u) => u.$1 > a ? u.$1 : a);
    print('  avg men/unit: ${avgMen.toStringAsFixed(0)}, '
        'avg quality: ${avgQ.toStringAsFixed(1)}, '
        'max quality: $maxQ, max men: $maxMen');
    print('  total men: $totalMen, total strength: ${totalStr.toStringAsFixed(0)}');

    void histogram(String label, List<(String, bool Function((int, int, int)))> buckets) {
      final line = StringBuffer('  $label: ');
      for (final (name, pred) in buckets) {
        final n = units.where(pred).length;
        line.write('$name=$n  ');
      }
      print(line.toString().trimRight());
    }

    histogram('quality', [
      ('Q1(roh)', (u) => u.$2 == 1),
      ('Q2-4', (u) => u.$2 >= 2 && u.$2 <= 4),
      ('Q5-9', (u) => u.$2 >= 5 && u.$2 <= 9),
      ('Q10-19', (u) => u.$2 >= 10 && u.$2 <= 19),
      ('Q20+', (u) => u.$2 >= 20),
    ]);
    histogram('size', [
      ('<50', (u) => u.$1 < 50),
      ('50-199', (u) => u.$1 >= 50 && u.$1 < 200),
      ('200-499', (u) => u.$1 >= 200 && u.$1 < 500),
      ('500-999', (u) => u.$1 >= 500 && u.$1 < 1000),
      ('1000+', (u) => u.$1 >= 1000),
    ]);
  }
}
