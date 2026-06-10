import '../rng/rng.dart';
import '../state/game_state.dart';

/// Annual global market price re-roll (ORIGINAL_GAME.md §9.1) — all
/// players trade at the same prices for the whole year.
void rollMarketPrices(GameState state, Rng rng) {
  state.grainPrice = (rng.nextInt(11) + 10) / 10; // [1.0, 2.0] T/Sack
  state.cattlePrice = (rng.nextInt(11) + 15) / 10; // [1.5, 2.5] T/Tier
}
