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
import '../rules/victory.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

/// Result of a pipeline step: the new state plus the events the step
/// emitted (already appended to `state.events`).
class TurnResult {
  TurnResult(this.state, this.events);

  final GameState state;
  final List<GameEvent> events;
}

/// Cap on `state.events`: the state is deep-copied on every action and
/// serialized on every auto-save, so the log must stay bounded. 1,000
/// events cover many rounds of recap/feed history; older ones are dropped
/// at turn completion and counted in `prunedEventCount`.
const int maxRetainedEvents = 1000;

void _pruneEvents(GameState state) {
  final excess = state.events.length - maxRetainedEvents;
  if (excess <= 0) return;
  state.events.removeRange(0, excess);
  state.prunedEventCount += excess;
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
  _pruneEvents(next);
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
  // Wars resolve INSIDE a turn (one global activeWar, §11): completing a
  // turn over an open war would leak it across turns and desync its
  // bookkeeping. The client disables "Zug beenden" at war; the V2 server
  // must reject such a submission — this is the engine-level backstop.
  if (state.activeWar != null) {
    throw StateError(
        'completeTurn: a war is still active — it must end (or its '
        'settlement finish) before the turn can complete');
  }
  final next = state.copy();
  final events = <GameEvent>[];
  // Whatever AI action phase was parked on this turn is over now.
  next.aiTurnActed = false;

  // End-of-turn for the active slot (§6.1 step 3): dynasty events,
  // pending assassinations, elimination checks.
  runDynastyPhase(next, next.currentPlayer, rng, events);
  resolveAssassinations(next, next.currentPlayer, rng, events);
  runEliminationChecks(next, next.currentPlayer, rng, events);

  final winner = checkWinCondition(next);
  if (winner != null) {
    // A war that overran the last rival this turn already emitted `gameWon`
    // from the settlement (so a human sees the popup right after the war);
    // don't emit a second one when the turn then completes — even if other
    // events (a build, a report) landed in the log since.
    if (!next.events.any((e) => e.type == 'gameWon')) {
      events.add(GameEvent(
        year: next.year,
        slot: winner,
        type: 'gameWon',
        visibility: EventVisibility.public,
      ));
    }
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    _pruneEvents(next);
    return TurnResult(next, events);
  }

  // Total extinction (every slot vacant) ends the game in a draw instead
  // of crashing on the next-slot search.
  if (!next.realms.any((r) => !r.isVacant)) {
    events.add(GameEvent(
      year: next.year,
      slot: 0,
      type: 'gameDraw',
      visibility: EventVisibility.public,
    ));
    next.rngSeed = rng.seed;
    next.events.addAll(events);
    _pruneEvents(next);
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
  _pruneEvents(next);
  return TurnResult(next, events);
}

/// Round rollover (§6.1): year += 1, global market prices re-roll, world
/// events (§18, Phase 4), normalization pass (§8.3), per-year flags reset.
void _startRound(GameState state, Rng rng, List<GameEvent> events) {
  state.year++;
  rollMarketPrices(state, rng);
  // §18 world events; every cause of land loss (earthquake, bankruptcy
  // seizure, war teardown) vacates a landless realm inline via
  // checkLandLoss — no round sweep needed.
  runWorldEvents(state, rng, events);
  normalizeTowns(state);
  // Re-seat any realm whose capital tile was lost this round (earthquake,
  // war claim, bankruptcy seizure): AI picks automatically, humans are
  // prompted with a `relocateCapital` decision.
  reseatLostCapitals(state, rng, events);
  runOfficePhase(state, rng, events); // Kurfürsten + elections (§17)

  for (final realm in state.realms) {
    // War weariness fades — but slowly: [wearinessDecayYears] consecutive
    // war-free years forgive ONE step of the escalating declaration penalty
    // and its recovery ceiling. "War-free" means the realm saw NO war at
    // all, defending included, exactly as it did while the defender still
    // carried `warThisYear` (aggressor-only since 2026-08-08; `lastWarYear`
    // is set for both sides). `state.year` was incremented above, so the
    // year that just ended is `year - 1`.
    if (realm.lastWarYear < state.year - 1) {
      realm.peaceYears++;
      if (realm.peaceYears >= wearinessDecayYears && realm.recentWars > 0) {
        realm.recentWars--;
        realm.peaceYears = 0;
      }
    } else {
      realm.peaceYears = 0;
    }
    realm.warThisYear = false; // wars: once per year per aggressor (§11.1)
  }

  // Orders against realms that went vacant (or merged away) can never
  // resolve — vacant slots take no turns — so drop them.
  state.assassinationOrders
      .removeWhere((o) => state.realm(o.targetSlot).isVacant);

  // Decisions are only created for human dynasties; one whose slot has
  // since turned AI or vacant (strife, capture, merge) is never surfaced
  // again and would sit in the state forever — drop it. The rules treat
  // an unresolved decision as its default anyway. A `warDefense` choice
  // whose war has already ended is equally moot.
  state.pendingDecisions.removeWhere((d) =>
      state.dynasty(d.decidingSlot).status != DynastyStatus.human ||
      state.realm(d.decidingSlot).isVacant ||
      ((d.type == 'warDefense' || d.type == 'warPlan') &&
          state.activeWar == null));
}

/// Per-turn upkeep for `state.currentPlayer` (§6.1 step 1): food →
/// growth/transitions → popularity → taxes → tribute → harbors → wages →
/// movement roll → per-turn flags. Emits one consolidated `turnUpkeep`
/// event (the §21.1 status report) plus any town-transition events.
void _beginTurn(GameState state, Rng rng, List<GameEvent> events) {
  final realm = state.realm(state.currentPlayer);
  if (realm.isVacant) return;

  _resolveShipReturns(state, realm, events);

  final food = runFoodAndPopulation(state, realm, rng, events);
  final economy = runEconomy(state, realm, rng);
  checkTitlePromotion(state, realm, events); // §16.2: every turn

  realm.movementPoints = rollMovementPoints(realm.popularity, rng);
  realm.soldGrainThisTurn = false;
  realm.soldCattleThisTurn = false;
  realm.investedThisTurn = false;
  realm.recruitedThisTurn = 0;
  realm.proposedThisTurnIds.clear();
  realm.assassinatedThisTurnSlots.clear();

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
      'harborIncome': economy.harborIncome,
      'wages': economy.wages,
      'taxPopularity': economy.taxPopularity,
      'popularity': realm.popularity,
      'movementPoints': realm.movementPoints,
    },
  ));
}

/// Trade ships sent on an earlier turn (§9.2) come home at the start of
/// this realm's turn: credit each haul and post a `shipsReturned` notice
/// (its profit/loss is the turn-start "Benachrichtigung").
void _resolveShipReturns(GameState state, Realm realm, List<GameEvent> events) {
  if (realm.pendingShipReturns.isEmpty) return;
  final due = realm.pendingShipReturns
      .where((r) => r.returnYear <= state.year)
      .toList();
  if (due.isEmpty) return;
  realm.pendingShipReturns.removeWhere((r) => r.returnYear <= state.year);
  for (final r in due) {
    realm.treasury += r.returned;
    events.add(GameEvent(
      year: state.year,
      slot: realm.slot,
      type: 'shipsReturned',
      visibility: EventVisibility.owner,
      payload: {'invested': r.invested, 'returned': r.returned},
    ));
  }
}

int _firstLivingSlot(GameState state) {
  for (final realm in state.realms) {
    if (!realm.isVacant) return realm.slot;
  }
  throw StateError('no living realms');
}

/// Next non-vacant slot after [current], wrapping past the last slot.
int _nextLivingSlot(GameState state, int current) {
  for (var i = 1; i <= state.realmCount; i++) {
    final slot = (current + i - 1) % state.realmCount + 1;
    final realm = state.realm(slot);
    if (!realm.isVacant) return slot;
  }
  throw StateError('no living realms');
}
