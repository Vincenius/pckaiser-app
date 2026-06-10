import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  test('movement roll: classEquivalent + random(6), always ≥ 1 (§6.3)', () {
    final rng = Rng(42);
    for (var titleClass = 1; titleClass <= 24; titleClass++) {
      final eq = movementClassEquivalent(titleClass);
      expect(eq, inInclusiveRange(1, 8));
      for (var i = 0; i < 50; i++) {
        final points = rollMovementPoints(titleClass, rng);
        expect(points, inInclusiveRange(eq, eq + 5));
        expect(points, greaterThanOrEqualTo(1),
            reason: 'every turn must allow at least one build');
      }
    }
  });
}
