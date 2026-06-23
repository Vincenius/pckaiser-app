import '../state/game_state.dart';

/// Protect-new-players rule (PROJECT_REQUIREMENTS.md): in the first ten
/// in-game years (1000–1009) random deaths (aging rolls, disease) and
/// eliminations (popularity crisis, bankruptcy) are suppressed — for AI
/// realms too. Deliberate assassinations still resolve normally, and wars
/// are gated to year ≥ 1010 anyway (§11.1).
///
/// Consulted by the dynasty/death modules (Phase 3) and the elimination
/// checks (Phase 4).
bool newPlayerProtectionActive(GameState state) => state.year <= 1009;

/// War declarations are forbidden before this year
/// ("Kriege sind erst ab dem Jahr 1010 erlaubt !", §11.1).
const int firstWarYear = 1010;

/// Earthquakes never strike before this year [DEVIATION: build-up grace
/// period; the original rolls earthquakes from year 1000]. Aligned with the
/// war/elimination gate (1010) so the protected first decade stays fully
/// disaster-free.
const int firstEarthquakeYear = 1010;
