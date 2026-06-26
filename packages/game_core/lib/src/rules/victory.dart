import '../state/game_state.dart';

/// §19.3 win check: the game is over when a single distinct non-null ruler
/// points at all still-ruled slots. Returns the winning slot, or null.
///
/// Lives in its own file (rather than the turn pipeline) so the war code
/// can consult it the moment a conquest leaves a sole ruler, without a
/// circular import back into the pipeline.
int? checkWinCondition(GameState state) {
  int? winnerSlot;
  int? winnerRuler;
  for (final realm in state.realms) {
    final ruler = realm.rulerId;
    if (ruler == null) continue;
    if (winnerRuler == null) {
      winnerRuler = ruler;
      winnerSlot = realm.slot;
    } else if (ruler != winnerRuler) {
      return null;
    }
  }
  return winnerSlot;
}
