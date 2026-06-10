import 'package:game_core/game_core.dart';

void main() {
  var state = startGame(
      newGame(GameSetup(
        humans: const [],
        reformationYear: 1020,
        ottomanYear: 1040,
        seed: 777,
      )),
      Rng(777)).state;
  var safety = 0;
  while (state.year < 1200 && safety++ < 8000) {
    final slot = state.currentPlayer;
    if (!state.realm(slot).isVacant &&
        state.dynasty(slot).status == DynastyStatus.ai) {
      state = runAiTurn(state, slot, Rng(state.rngSeed)).state;
    }
    state = completeTurn(state, Rng(state.rngSeed)).state;
    if (state.events.isNotEmpty && state.events.last.type == 'gameWon') break;
  }
  final counts = <String, int>{};
  for (final e in state.events) {
    counts[e.type] = (counts[e.type] ?? 0) + 1;
  }
  print('final year: ${state.year}, events: ${state.events.length}');
  final interesting = ['warDeclared', 'battle', 'rulerCaptured', 'warWon',
    'tileConquered', 'plunder', 'assassination', 'disease', 'earthquake',
    'reformation', 'ottomanInvasion', 'crowned', 'bankruptcy',
    'internalStrife', 'merchantFounder', 'wedding', 'birth', 'succession',
    'gameWon', 'townPromoted', 'realmsMerged'];
  for (final k in interesting) {
    print('  $k: ${counts[k] ?? 0}');
  }
  final living = state.realms.where((r) => !r.isVacant).length;
  print('living realms: $living');
}
