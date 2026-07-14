/// Player-facing prices and their gates that don't belong to a larger
/// rules domain (troop costs live in rules/troops.dart, building costs in
/// Building.cost). The ONE home for every number the client shows on a
/// button and the engine charges on apply — label and gate can never
/// drift apart.
library;

import '../state/constants.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

/// Voluntary "Sitz verlegen" fee (§6.2 `[DESIGNED]`); re-seating a LOST
/// capital is free (see `_relocateCapital`).
const int relocateCapitalCost = 5000;

/// "(A)breißen" — demolishing a field/Burg/Palast/Hafen (§4).
const int demolishCost = 100;

/// Trade-ship investment cap per owned Hafen (§9.2).
const int shipInvestmentPerHafen = 600;

/// Largest trade-ship stake [realm] may send this turn (§9.2).
int shipInvestmentCap(Realm realm) =>
    realm.tileCount[Building.hafen] * shipInvestmentPerHafen;

/// Conversion price by target religion (§4): katholisch free,
/// evangelisch 500 T, moslemisch 1,000 T.
int religionChangeCost(int religion) => switch (religion) {
      Religion.evangelisch => 500,
      Religion.moslemisch => 1000,
      _ => 0,
    };

/// Whether [religion] exists yet (§15.2) — inclusive of the event year
/// itself: the Reformation/Ottoman event fires in the round where
/// `year == eventYear` and its announcement invites the conversion.
bool religionAvailable(GameState state, int religion) => switch (religion) {
      Religion.evangelisch => state.year >= state.reformationYear,
      Religion.moslemisch => state.year >= state.ottomanYear,
      _ => true,
    };
