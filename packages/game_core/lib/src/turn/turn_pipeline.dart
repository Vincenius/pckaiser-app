import '../rng/rng.dart';
import '../rules/dynasty.dart';
import '../rules/economy.dart';
import '../rules/espionage.dart';
import '../rules/events.dart';
import '../rules/market.dart';
import '../rules/movement.dart';
import '../rules/offices.dart';
import '../rules/population.dart';
import '../rules/titles.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';

/// Result of a pipeline step: the new state plus the events the step
/// emitted (already appended to `state.events`).
class TurnResult {
  TurnResult(this.state, this.events);

  final GameState state;
  final List<GameEvent> events;
}

/// Starts the game (§6.1): rolls the world into year 1000 and runs the
/// first slot's upkeep. Call once on a fresh [GameState] from `newGame`.
TurnResult startGame(GameState state, Rng rng) {
  if (state.year != 999) {
    throw StateError('startGame expects a fresh year-999 state');
  }
  final next = state.copy();
  final events = <GameEvent>[];
  _startRound(next, rng, events);
  next.currentPlayer = _firstLivingSlot(next);
  _beginTurn(next, rng, events);
  next.rngSeed = rng.seed;
  next.events.addAll(events);
  return TurnResult(next, events);
}

/// Completes the current player's turn (§6.1 step 3) and advances to the
/// next living slot's upkeep — rolling the round (year, prices, world
/// phase) when control wraps. The local loop auto-saves after this call;
/// the server runs AI turns in between.
///
/// Returns with `state.currentPlayer` set to the next slot whose action
/// phase may begin — or with a `gameWon` event if the game is over.
TurnResult completeTurn(GameState state, Rng rng) {
  final next = state.copy();
  final events = <GameEvent>[];

  // End-of-turn for the active slot (§6.1 step 3): dynasty events,
  // pending assassinations, elimination checks.
  runDynastyPhase(next, next.currentPlayer, rng, events);
  resolveAssassinations(next, next.currentPlayer, rng, events);
  runEliminationChecks(next, next.currentPlayer, rng, events);

  final winner = checkWinCondition(next);
  if (winner != null) {
    events.add(GameEvent(
      year: next.year,
      slot: winner,
      type: 'gameWon',
      visibility: EventVisibility.public,
    ));
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    return TurnResult(next, events);
  }

  final previous = next.currentPlayer;
  next.currentPlayer = _nextLivingSlot(next, previous);
  if (next.currentPlayer <= previous) {
    _startRound(next, rng, events); // control wrapped: new year
  }
  _beginTurn(next, rng, events);

  next.rngSeed = rng.seed;
  next.events.addAll(events);
  return TurnResult(next, events);
}

/// §19.3 win check: the game is over when a single distinct non-null ruler
/// points at all still-ruled slots. Returns the winning slot, or null.
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

/// Round rollover (§6.1): year += 1, global market prices re-roll, world
/// events (§18, Phase 4), normalization pass (§8.3), per-year flags reset.
void _startRound(GameState state, Rng rng, List<GameEvent> events) {
  state.year++;
  rollMarketPrices(state, rng);
  runWorldEvents(state, rng, events); // §18
  normalizeTowns(state);
  runOfficePhase(state, rng, events); // Kurfürsten + elections (§17)

  for (final realm in state.realms) {
    realm.warThisYear = false; // wars: once per year per player (§11.1)
  }
}

/// Per-turn upkeep for `state.currentPlayer` (§6.1 step 1): food →
/// growth/transitions → popularity → taxes → tribute → harbors → wages →
/// movement roll → per-turn flags. Emits one consolidated `turnUpkeep`
/// event (the §21.1 status report) plus any town-transition events.
void _beginTurn(GameState state, Rng rng, List<GameEvent> events) {
  final realm = state.realm(state.currentPlayer);
  if (realm.isVacant) return;

  final food = runFoodAndPopulation(state, realm, rng, events);
  final economy = runEconomy(state, realm, rng);
  checkTitlePromotion(state, realm, events); // §16.2: every turn

  realm.movementPoints = rollMovementPoints(realm.titleClass, rng);
  realm.soldGrainThisTurn = false;
  realm.soldCattleThisTurn = false;
  realm.investedThisTurn = false;
  realm.proposedMarriageThisTurn = false;

  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'turnUpkeep',
    visibility: EventVisibility.owner,
    payload: {
      'grainYield': food.grainYield,
      'livestockYield': food.livestockYield,
      'surplusPercent': food.surplusPercent,
      'populationDelta': food.populationDelta,
      'famineLoss': food.famineLoss,
      'tax': economy.tax,
      'tribute': economy.tribute,
      'potCollected': economy.potCollected,
      'harborIncome': economy.harborIncome,
      'wages': economy.wages,
      'popularity': realm.popularity,
      'movementPoints': realm.movementPoints,
    },
  ));
}

int _firstLivingSlot(GameState state) {
  for (final realm in state.realms) {
    if (!realm.isVacant) return realm.slot;
  }
  throw StateError('no living realms');
}

/// Next non-vacant slot after [current], wrapping past slot 30.
int _nextLivingSlot(GameState state, int current) {
  for (var i = 1; i <= World.realmCount; i++) {
    final slot = (current + i - 1) % World.realmCount + 1;
    final realm = state.realm(slot);
    if (!realm.isVacant) return slot;
  }
  throw StateError('no living realms');
}
