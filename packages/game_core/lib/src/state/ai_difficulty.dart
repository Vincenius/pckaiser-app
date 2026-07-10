/// AI opponent difficulty, chosen once at game setup (local and online)
/// and fixed for the whole game. `[DESIGNED]` — the original has a single
/// AI script; the levels only change HOW the script plays (build
/// priorities, military planning, assassinations), never the rules and
/// never the AI's resources: no gold or growth boni on any level. Like the
/// original script, the AI plays on the unfiltered state (its war movement
/// always has, see `_warTarget`); schwer merely uses that state for its
/// target picks too.
enum AiDifficulty {
  leicht,
  mittel,
  schwer;

  /// Parses a serialized value; unknown/missing values fall back to
  /// [mittel] (the pre-difficulty behaviour, so old saves play unchanged
  /// and a future level degrades gracefully instead of crashing).
  static AiDifficulty fromName(String? name) =>
      values.asNameMap()[name] ?? AiDifficulty.mittel;
}
