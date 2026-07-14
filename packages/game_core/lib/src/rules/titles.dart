import '../data/tables.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

/// Whether a stored title class is the female form (`class + 12`, §16.1).
bool isFemaleTitleClass(int titleClass) => titleClass > 12;

/// The gender-neutral rank of a stored title class — THE one place the
/// `class − 12` female-form convention is decoded (§16.1).
int baseTitleClass(int titleClass) =>
    isFemaleTitleClass(titleClass) ? titleClass - 12 : titleClass;

/// Christian-equivalent rank: Muslim classes 9–12 map to 1/3/6/8 for the
/// tables that only exist on the Christian ladder — the §6.3 movement roll
/// and the §19.2 bankruptcy limits share this ONE mapping.
int christianEquivalentClass(int titleClass) {
  const muslimEquivalent = {9: 1, 10: 3, 11: 6, 12: 8};
  final base = baseTitleClass(titleClass);
  return muslimEquivalent[base] ?? base;
}

/// Prestige score (§16.2):
/// `population + treasury + 10×weight + 1,000×Häfen + 10,000×Burgen +
/// 20,000×Paläste`.
int prestigeScore(Realm realm) =>
    realm.population +
    realm.treasury +
    10 * realm.popularity +
    1000 * realm.tileCount[Building.hafen] +
    10000 * realm.tileCount[Building.burg] +
    20000 * realm.tileCount[Building.palast];

/// Promotion thresholds by (titleClass, minimum score); the ladder floor
/// (Ritter/Scheich) has none. Titles never demote.
const List<(int, int)> _christianLadder = [
  (2, 15000),
  (3, 20000),
  (4, 30000),
  (5, 40000),
  (6, 50000),
  (7, 75000),
  (8, 100000),
];
const List<(int, int)> _muslimLadder = [
  (10, 20000),
  (11, 50000),
  (12, 80000),
];

/// Switches a realm's title onto the other religion's ladder when its
/// current class belongs to the wrong one (§4/§16.1): conversion to Islam
/// resets to Scheich (9), conversion away from Islam to Ritter (1) — the
/// per-turn promotion check climbs back by prestige. Catholic↔Protestant
/// share the Christian ladder, so nothing changes there.
void switchTitleLadder(Realm realm, int religion) {
  final female = isFemaleTitleClass(realm.titleClass);
  final base = baseTitleClass(realm.titleClass);
  if (religion == Religion.moslemisch) {
    if (base <= 8) realm.titleClass = 9 + (female ? 12 : 0);
  } else if (base >= 9) {
    realm.titleClass = 1 + (female ? 12 : 0);
  }
}

/// Aligns the stored form of a realm's title with its ruler's gender
/// (female forms are `class + 12`, §16.1); the rank itself stays the
/// realm's. Must run wherever the ruler pointer changes hands (succession,
/// inheritance, strife) — otherwise an inherited realm keeps the
/// predecessor's gendered form.
void regenderTitle(GameState state, Realm realm) {
  final ruler = state.person(realm.rulerId);
  if (ruler == null) return;
  realm.titleClass = baseTitleClass(realm.titleClass) + (ruler.isMale ? 0 : 12);
}

/// §16.2 promotion check ("checked every turn, every player"): promotes
/// the realm's title when the prestige score reaches a higher class.
void checkTitlePromotion(GameState state, Realm realm, List<GameEvent> events) {
  if (realm.isVacant) return;
  final female = isFemaleTitleClass(realm.titleClass);
  final current = baseTitleClass(realm.titleClass);
  final muslim = state.dynasty(realm.slot).religion == Religion.moslemisch;
  final ladder = muslim ? _muslimLadder : _christianLadder;

  final score = prestigeScore(realm);
  var target = current;
  for (final (cls, threshold) in ladder) {
    if (score >= threshold && cls > target) target = cls;
  }
  if (target == current) return;

  realm.titleClass = target + (female ? 12 : 0);
  events.add(GameEvent(
    year: state.year,
    slot: realm.slot,
    type: 'titlePromoted',
    visibility: EventVisibility.public,
    payload: {
      'title': titleName(realm.titleClass),
      'titleClass': realm.titleClass,
    },
  ));
}
