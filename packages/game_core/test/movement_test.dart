import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('movement roll: max(minimum, popularity/divisor) + random(6)', () {
    final rng = Rng(42);
    for (var popularity = 0; popularity <= 100; popularity++) {
      final base =
          popularity ~/ movementPopularityDivisor < movementPointsMinimum
              ? movementPointsMinimum
              : popularity ~/ movementPopularityDivisor;
      for (var i = 0; i < 20; i++) {
        final points = rollMovementPoints(popularity, rng);
        expect(points, inInclusiveRange(base, base + 5));
        expect(points, greaterThanOrEqualTo(1),
            reason: 'every turn must allow at least one build');
      }
    }
  });

  test('a loved realm out-builds a hated one of any size', () {
    final rng = Rng(7);
    var loved = 0;
    var hated = 0;
    for (var i = 0; i < 500; i++) {
      loved += rollMovementPoints(100, rng);
      hated += rollMovementPoints(20, rng);
    }
    expect(loved, greaterThan(hated));
  });
}
