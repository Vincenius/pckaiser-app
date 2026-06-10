/// Pure Dart game logic for the PC Kaiser mobile clone, shared by the
/// Flutter client (local mode) and the Dart shelf server (online mode).
///
/// All rules are pure and deterministic: `(state, action, rng) → state`,
/// with the RNG injected (see ARCHITECTURE.md).
library;

export 'src/actions/apply_action.dart';
export 'src/actions/player_action.dart';
export 'src/data/tables.dart';
export 'src/map/map_generator.dart';
export 'src/rng/rng.dart';
export 'src/rules/dynasty.dart';
export 'src/rules/economy.dart';
export 'src/rules/espionage.dart';
export 'src/rules/events.dart';
export 'src/rules/market.dart';
export 'src/rules/movement.dart';
export 'src/rules/offices.dart';
export 'src/rules/population.dart';
export 'src/rules/protection.dart';
export 'src/rules/titles.dart';
export 'src/rules/troops.dart';
export 'src/rules/war.dart';
export 'src/setup/new_game.dart';
export 'src/state/war.dart';
export 'src/turn/turn_pipeline.dart';
export 'src/state/chronicle.dart';
export 'src/state/constants.dart';
export 'src/state/dynasty.dart';
export 'src/state/election.dart';
export 'src/state/game_event.dart';
export 'src/state/game_state.dart';
export 'src/state/intel_report.dart';
export 'src/state/pending_decision.dart';
export 'src/state/person.dart';
export 'src/state/realm.dart';
export 'src/state/town.dart';
export 'src/state/troop.dart';
export 'src/state/world_map.dart';
export 'src/visibility/visible_state.dart';
