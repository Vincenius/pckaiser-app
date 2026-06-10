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
