import '../data/tables.dart';
import '../map/map_generator.dart';
import '../rng/rng.dart';
import '../state/constants.dart';
import '../state/dynasty.dart';
import '../state/game_state.dart';
import '../state/person.dart';
import '../state/realm.dart';
import '../state/town.dart';
import '../state/world_map.dart';

/// Setup years below this are rejected ("Das ist zu früh !!!", §5).
const int minEventYear = 1011;

/// One human player's setup choices (§5).
class HumanPlayerSetup {
  HumanPlayerSetup({
    required this.founderName,
    required this.gender,
    required this.countrySlot,
    required this.dorfName,
  });

  final String founderName;

  /// 0 = male ("Männlich"), 1 = female ("Weiblich").
  final int gender;

  /// Realm slot 1–30 = country index in [countryNames].
  final int countrySlot;

  /// Name of the first Dorf.
  final String dorfName;
}

/// Configuration for a new game.
class GameSetup {
  GameSetup({
    required this.humans,
    required this.reformationYear,
    required this.ottomanYear,
    required this.seed,
    this.warStartYear = 1010,
    this.genderEqualSuccession = true,
  }) {
    // 1–16 humans for real games; 0 is allowed for headless simulations
    // (e.g. the full-AI smoke test).
    if (humans.length > 16) {
      throw ArgumentError('at most 16 human players, got ${humans.length}');
    }
    // "Das ist zu früh !!!" — each year validated independently (§5).
    if (reformationYear < minEventYear) {
      throw ArgumentError('Reformation year must be ≥ $minEventYear');
    }
    if (ottomanYear < minEventYear) {
      throw ArgumentError('Ottoman year must be ≥ $minEventYear');
    }
  }

  final List<HumanPlayerSetup> humans;
  final int reformationYear;
  final int ottomanYear;
  final int seed;

  /// First year war declarations are allowed (§11.1; original 1010).
  final int warStartYear;

  /// Deviation from the original (default on for new games): gender-neutral
  /// succession — the eldest child inherits regardless of gender and the
  /// Islamic succession crisis (§15.5) never eliminates a player. See
  /// [GameState.genderEqualSuccession].
  final bool genderEqualSuccession;
}

/// Creates a fresh game world (ORIGINAL_GAME.md §5): random map, 30
/// dynasties (humans on their chosen country slots, AI everywhere else),
/// each with a founder, a 5-tile starting cross and 1,000 Taler.
///
/// All starting dynasties are Catholic — at year 999 the Reformation and
/// Ottoman years are always in the future (§15.2).
GameState newGame(GameSetup setup) {
  final rng = Rng(setup.seed);
  final map = generateMap(rng);
  final componentSize = _landComponentSizes(map);

  final humanBySlot = <int, int>{};
  for (var i = 0; i < setup.humans.length; i++) {
    final slot = setup.humans[i].countrySlot;
    if (slot < 1 || slot > World.realmCount) {
      throw ArgumentError('country slot $slot out of range 1–30');
    }
    if (humanBySlot.containsKey(slot)) {
      throw ArgumentError('country slot $slot picked twice');
    }
    humanBySlot[slot] = i;
  }

  final realms = <Realm>[];
  final dynasties = <Dynasty>[];
  final persons = <int, Person>{};
  var nextPersonId = 1;

  for (var slot = 1; slot <= World.realmCount; slot++) {
    final humanIndex = humanBySlot[slot];
    final human = humanIndex == null ? null : setup.humans[humanIndex];

    final gender = human?.gender ?? rng.nextInt(2);
    final founderRaw = human?.founderName ??
        (gender == 0
            ? europeanMaleNames[rng.nextInt(europeanMaleNames.length)]
            : europeanFemaleNames[rng.nextInt(europeanFemaleNames.length)]);
    final founderName = clampName(founderRaw);
    final dorfName = clampName(human?.dorfName ?? cityNames[slot - 1]);

    final founder = Person(
      id: nextPersonId++,
      name: founderName,
      age: 17 + rng.nextInt(5),
      dynasty: slot,
      gender: gender,
    );
    persons[founder.id] = founder;

    dynasties.add(Dynasty(
      index: slot,
      status: human == null ? DynastyStatus.ai : DynastyStatus.human,
      humanPlayer: humanIndex,
      religion: Religion.katholisch,
      memberIds: [founder.id],
    ));

    final realm = Realm(
      slot: slot,
      // Founding title: Ritter (1); female founders use the female form
      // (class + 12, §16.1). Muslim founding titles only occur for
      // replacement dynasties after the Ottoman year (§15.2, §19).
      titleClass: gender == 0 ? 1 : 13,
      treasury: 1000,
      popularity: 50,
      rulerId: founder.id,
    );
    _placeStartingCross(map, realm, rng,
        dorfName: dorfName, componentSize: componentSize);
    realms.add(realm);
  }

  return GameState(
    year: 999,
    reformationYear: setup.reformationYear,
    ottomanYear: setup.ottomanYear,
    warStartYear: setup.warStartYear,
    genderEqualSuccession: setup.genderEqualSuccession,
    persons: persons,
    nextPersonId: nextPersonId,
    currentPlayer: 1,
    map: map,
    realms: realms,
    dynasties: dynasties,
    rngSeed: rng.seed,
  );
}

/// A starting position must sit on a connected landmass of at least this
/// many tiles, so no realm starts boxed in on a small island [DEVIATION:
/// the original accepts any spot with > 2 land neighbors]. On degenerate
/// maps where no component reaches the threshold, the largest one is
/// accepted instead.
const int _minStartComponent = 50;

/// Size of each land tile's 4-connected component, indexed like the map
/// (water tiles get 0). One flood-fill pass over the finished map.
List<int> _landComponentSizes(WorldMap map) {
  final size = List<int>.filled(map.terrain.length, 0);
  final componentOf = List<int>.filled(map.terrain.length, -1);
  final componentSizes = <int>[];

  for (var start = 0; start < map.terrain.length; start++) {
    if (componentOf[start] != -1 || !Terrain.isLand(map.terrain[start])) {
      continue;
    }
    final id = componentSizes.length;
    final stack = [start];
    componentOf[start] = id;
    var count = 0;
    while (stack.isNotEmpty) {
      final index = stack.removeLast();
      count++;
      final x = index % map.width;
      final y = index ~/ map.width;
      for (final (dx, dy) in _scanOrder) {
        final nx = x + dx;
        final ny = y + dy;
        if (!map.inBounds(nx, ny)) continue;
        final ni = map.index(nx, ny);
        if (componentOf[ni] == -1 && Terrain.isLand(map.terrain[ni])) {
          componentOf[ni] = id;
          stack.add(ni);
        }
      }
    }
    componentSizes.add(count);
  }

  for (var i = 0; i < size.length; i++) {
    if (componentOf[i] != -1) size[i] = componentSizes[componentOf[i]];
  }
  return size;
}

/// Shoreline variants that disqualify a starting position's neighbors (§5).
const Set<int> _forbiddenShoreline = {7, 8, 9, 11, 12, 13, 15, 16};

/// Neighbor scan order −X, +X, +Y, −Y (§5) as (dx, dy) pairs.
const List<(int, int)> _scanOrder = [(-1, 0), (1, 0), (0, 1), (0, -1)];

/// Picks the starting position and claims the 5-tile cross (§5):
/// Burg in the center (the capital), the first land neighbor becomes the
/// named Dorf, other land neighbors Kornfeld/Weide, water neighbors Hafen.
void _placeStartingCross(
  WorldMap map,
  Realm realm,
  Rng rng, {
  required String dorfName,
  required List<int> componentSize,
}) {
  var largestComponent = 0;
  for (final s in componentSize) {
    if (s > largestComponent) largestComponent = s;
  }
  final minComponent = largestComponent < _minStartComponent
      ? largestComponent
      : _minStartComponent;

  int x, y;
  var attempts = 0;
  for (;;) {
    if (++attempts > 100000) {
      // The original re-rolls forever; on a degenerate map we fail loudly
      // instead of hanging.
      throw StateError('no valid starting position for slot ${realm.slot}');
    }
    x = rng.nextInt(78) + 1;
    y = rng.nextInt(42) + 1;
    if (!map.isLandAt(x, y) || map.ownerAt(x, y) != World.niemand) continue;
    if (componentSize[map.index(x, y)] < minComponent) continue; // island

    var landNeighbors = 0;
    var ok = true;
    for (final (dx, dy) in _scanOrder) {
      final terrain = map.terrainAt(x + dx, y + dy);
      if (map.ownerAt(x + dx, y + dy) != World.niemand ||
          _forbiddenShoreline.contains(terrain)) {
        ok = false;
        break;
      }
      if (Terrain.isLand(terrain)) landNeighbors++;
    }
    if (ok && landNeighbors > 2) break;
  }

  final slot = realm.slot;

  void claim(int cx, int cy, int building) {
    map.owner[map.index(cx, cy)] = slot;
    map.building[map.index(cx, cy)] = building;
    realm.tileCount[building]++;
  }

  claim(x, y, Building.burg);
  realm
    ..capitalX = x
    ..capitalY = y
    ..cursorX = x
    ..cursorY = y;

  var dorfPlaced = false;
  for (final (dx, dy) in _scanOrder) {
    final nx = x + dx;
    final ny = y + dy;
    if (map.isWaterAt(nx, ny)) {
      claim(nx, ny, Building.hafen);
    } else if (!dorfPlaced) {
      dorfPlaced = true;
      claim(nx, ny, Building.dorf);
      final town = Town(
        name: dorfName,
        population: 75 + rng.nextInt(50),
        troopCapacity: 25,
        garrison: 0,
        buildingType: Building.dorf,
        x: nx,
        y: ny,
      );
      realm.towns.add(town);
      realm.population += town.population;
      realm.troopCapacity += town.troopCapacity;
    } else {
      claim(
          nx,
          ny,
          map.terrainAt(nx, ny) == Terrain.berg
              ? Building.weide
              : Building.kornfeld);
    }
  }
}
