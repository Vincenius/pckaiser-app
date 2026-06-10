import '../rng/rng.dart';

/// Christian-equivalent class for the movement roll (§6.3): Muslim classes
/// 9–12 map to 1/3/6/8; female classes are `class − 12`.
int movementClassEquivalent(int titleClass) {
  var cls = titleClass > 12 ? titleClass - 12 : titleClass;
  const muslimEquivalent = {9: 1, 10: 3, 11: 6, 12: 8};
  cls = muslimEquivalent[cls] ?? cls;
  return cls;
}

/// Movement-point roll (ORIGINAL_GAME.md §6.3):
/// `points = classEquivalent + random(6)`.
int rollMovementPoints(int titleClass, Rng rng) =>
    movementClassEquivalent(titleClass) + rng.nextInt(6);
