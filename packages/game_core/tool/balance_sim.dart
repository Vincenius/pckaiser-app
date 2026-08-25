import 'dart:math' as math;

import 'package:game_core/game_core.dart';

/// Runaway-leader balance probe.
///
/// Usage: `dart tool/balance_sim.dart [seeds] [leicht|mittel|schwer]`
///
/// Runs N all-AI worlds and reports how CONCENTRATED the map gets: the land
/// share of the biggest realm, how often the early leader is still the
/// leader at the end, and whether a realm from the bottom half ever closes
/// the gap. Those are the numbers behind "a small realm can never catch up".
/// Wars/conquests are reported alongside so a fix cannot pass by simply
/// freezing the map.
void main(List<String> args) {
  final seeds = int.tryParse(args.isNotEmpty ? args.first : '') ?? 12;
  final difficulty = AiDifficulty.fromName(args.length > 1 ? args[1] : null);

  const midYear = 1100; // established-leader snapshot
  const endYear = 1200;

  final topShare = <double>[];
  final gini = <double>[];
  final living = <int>[];
  final leaderKept = <bool>[];
  final laggardClosed = <bool>[]; // a bottom-half realm reached 80% of the top
  final gapRatio = <double>[]; // top land / median land at endYear
  final popTop = <double>[];
  final popRest = <double>[];
  // Calibration: the OLD title-based roll vs. the NEW popularity-based one,
  // averaged over every realm-turn. Keeping these close keeps the global
  // expansion tempo where it was — the point is to change WHO gets the
  // Züge, not how many the world has.
  var oldBaseSum = 0.0;
  var newBaseSum = 0.0;
  var realmTurns = 0;
  var wars = 0;
  var conquests = 0;
  var battles = 0;
  var won = 0;

  for (var s = 0; s < seeds; s++) {
    final seed = 1000 + s * 37;
    final start = startGame(
        newGame(GameSetup(
          humans: const [],
          reformationYear: 1020,
          ottomanYear: 1040,
          aiDifficulty: difficulty,
          seed: seed,
        )),
        Rng(seed));
    var state = start.state;
    var safety = 0;
    Map<int, int>? midLand;

    void tally(Iterable<GameEvent> events) {
      for (final e in events) {
        switch (e.type) {
          case 'warDeclared':
            wars++;
          case 'tileConquered':
            conquests++;
          case 'battle':
            battles++;
          case 'gameWon':
            won++;
        }
      }
    }

    tally(start.events);
    while (state.year < endYear && safety++ < 12000) {
      final slot = state.currentPlayer;
      if (!state.realm(slot).isVacant &&
          state.dynasty(slot).status == DynastyStatus.ai) {
        final r = runAiTurn(state, slot, Rng(state.rngSeed));
        state = r.state;
        tally(r.events);
      }
      final r = completeTurn(state, Rng(state.rngSeed));
      state = r.state;
      tally(r.events);
      for (final r2 in state.realms) {
        if (r2.isVacant) continue;
        realmTurns++;
        oldBaseSum += _titleEquivalent(r2.titleClass);
        newBaseSum += math.max(
            movementPointsMinimum, r2.popularity ~/ movementPopularityDivisor);
      }
      if (midLand == null && state.year >= midYear) midLand = _land(state);
      if (r.events.any((e) => e.type == 'gameWon')) break;
    }

    final land = _land(state);
    final total = land.values.fold(0, (a, b) => a + b);
    if (total == 0) continue;
    final sorted = land.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    topShare.add(sorted.first.value / total);
    gini.add(_gini([for (final e in sorted) e.value]));
    living.add(sorted.length);
    final median = sorted[sorted.length ~/ 2].value;
    gapRatio.add(median == 0 ? 99 : sorted.first.value / median);

    // Popularity of the biggest realm vs. everyone else.
    popTop.add(state.realm(sorted.first.key).popularity.toDouble());
    if (sorted.length > 1) {
      popRest.add(sorted
              .skip(1)
              .fold(0.0, (a, e) => a + state.realm(e.key).popularity) /
          (sorted.length - 1));
    }

    if (midLand != null && midLand.isNotEmpty) {
      final midSorted = midLand.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      leaderKept.add(midSorted.first.key == sorted.first.key);
      // Bottom half at midYear: did any of them reach 80% of the final top?
      final bottom =
          midSorted.skip((midSorted.length + 1) ~/ 2).map((e) => e.key);
      laggardClosed.add(
          bottom.any((slot) => (land[slot] ?? 0) >= 0.8 * sorted.first.value));
    }
  }

  String pct(List<double> xs) =>
      xs.isEmpty ? '-' : '${(_avg(xs) * 100).toStringAsFixed(1)}%';
  String num1(List<double> xs) =>
      xs.isEmpty ? '-' : _avg(xs).toStringAsFixed(1);
  String rate(List<bool> xs) => xs.isEmpty
      ? '-'
      : '${(100 * xs.where((b) => b).length / xs.length).toStringAsFixed(0)}%';

  print('seeds: $seeds  difficulty: ${difficulty.name}  '
      'years: 1000-$endYear');
  print('  top land share      : ${pct(topShare)}   (lower = less runaway)');
  print('  land gini           : ${num1(gini)}');
  print('  top / median land   : ${num1(gapRatio)}x');
  print(
      '  living realms       : ${num1(living.map((e) => e.toDouble()).toList())}');
  print(
      '  early leader still #1: ${rate(leaderKept)}  (lower = more catch-up)');
  print(
      '  laggard closed to 80%: ${rate(laggardClosed)}  (higher = more catch-up)');
  print('  popularity top / rest: ${num1(popTop)} / ${num1(popRest)}');
  print('  Zuege base old(title)/new(pop): '
      '${(oldBaseSum / realmTurns).toStringAsFixed(2)} / '
      '${(newBaseSum / realmTurns).toStringAsFixed(2)}  (+2.5 random)');
  print('  wars: $wars  battles: $battles  conquests: $conquests  '
      'games decided: $won');
}

Map<int, int> _land(GameState state) {
  final counts = <int, int>{};
  final map = state.map;
  for (var i = 0; i < map.owner.length; i++) {
    final o = map.owner[i];
    if (o == World.niemand) continue;
    if (state.realm(o).isVacant) continue;
    counts[o] = (counts[o] ?? 0) + 1;
  }
  return counts;
}

double _avg(List<double> xs) => xs.fold(0.0, (a, b) => a + b) / xs.length;

double _gini(List<int> values) {
  if (values.isEmpty) return 0;
  final xs = List<int>.of(values)..sort();
  final n = xs.length;
  final sum = xs.fold(0, (a, b) => a + b);
  if (sum == 0) return 0;
  var cum = 0.0;
  for (var i = 0; i < n; i++) {
    cum += (2 * (i + 1) - n - 1) * xs[i];
  }
  return cum / (n * sum);
}

/// The pre-2026-08-24 movement base: the Christian-equivalent title class.
int _titleEquivalent(int titleClass) {
  final base = titleClass > 12 ? titleClass - 12 : titleClass;
  return const {9: 1, 10: 3, 11: 6, 12: 8}[base] ?? base;
}
