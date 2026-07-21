/// World map size, chosen once at game setup (local and online) and fixed
/// for the whole game. `[DESIGNED]` — the original only knows the 80×44
/// world with 30 realms; smaller maps shrink the tile grid AND the number
/// of realm slots in play, with the map generator's land-patch/lake counts
/// scaled by area so land density stays the same. Existing saves (always
/// 80×44 / 30 realms) load unchanged — the map dimensions travel inside the
/// serialized map, the realm count is the length of the realms list.
enum MapSize {
  klein(
    width: 48,
    height: 28,
    landPatches: 38,
    lakes: 10,
    defaultRealmCount: 12,
    minRealmCount: 6,
    maxRealmCount: 16,
  ),
  mittel(
    width: 64,
    height: 36,
    landPatches: 65,
    lakes: 16,
    defaultRealmCount: 20,
    minRealmCount: 8,
    maxRealmCount: 24,
  ),
  gross(
    width: 80,
    height: 44,
    landPatches: 100,
    lakes: 25,
    defaultRealmCount: 30,
    minRealmCount: 10,
    maxRealmCount: 30,
  );

  const MapSize({
    required this.width,
    required this.height,
    required this.landPatches,
    required this.lakes,
    required this.defaultRealmCount,
    required this.minRealmCount,
    required this.maxRealmCount,
  });

  /// Tile grid dimensions ([gross] = the original 80×44, §3.1).
  final int width;
  final int height;

  /// Map-generator inputs ([gross] = the original 100/25, §3.2), scaled by
  /// tile area so every size has roughly the same land share.
  final int landPatches;
  final int lakes;

  /// Realm slots in play when the setup does not override them. Slots are
  /// always 1..realmCount, so the original country/village name tables
  /// (indices 1–30) keep working on every size.
  final int defaultRealmCount;

  /// Setup-selectable realm-count range. The minimum keeps elections and
  /// diplomacy meaningful (Kurfürsten seats simply stay partially vacant
  /// below 7 eligible rulers); the maximum is bounded by the 30 historic
  /// realm slots and, on smaller maps, by the land available for the §5
  /// starting crosses.
  final int minRealmCount;
  final int maxRealmCount;

  /// Parses a serialized value; unknown/missing values fall back to
  /// [gross] (the original world, so old documents play unchanged).
  static MapSize fromName(String? name) =>
      values.asNameMap()[name] ?? MapSize.gross;
}
