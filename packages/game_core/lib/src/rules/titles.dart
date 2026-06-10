import '../data/tables.dart';
import '../state/constants.dart';
import '../state/game_event.dart';
import '../state/game_state.dart';
import '../state/realm.dart';

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
  (2, 15000), (3, 20000), (4, 30000), (5, 40000), (6, 50000),
  (7, 75000), (8, 100000),
];
const List<(int, int)> _muslimLadder = [
  (10, 20000), (11, 50000), (12, 80000),
];

/// §16.2 promotion check ("checked every turn, every player"): promotes
/// the realm's title when the prestige score reaches a higher class.
void checkTitlePromotion(GameState state, Realm realm,
    List<GameEvent> events) {
  if (realm.isVacant) return;
  final female = realm.titleClass > 12;
  final current = female ? realm.titleClass - 12 : realm.titleClass;
  final muslim =
      state.dynasty(realm.slot).religion == Religion.moslemisch;
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
