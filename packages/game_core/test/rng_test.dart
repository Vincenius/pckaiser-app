import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('Rng', () {
    test('is deterministic for the same seed', () {
      final a = Rng(12345);
      final b = Rng(12345);
      for (var i = 0; i < 1000; i++) {
        expect(a.nextInt(100), b.nextInt(100));
      }
      expect(a.seed, b.seed);
    });

    test('matches the Borland Pascal LCG', () {
      // seed' = seed * 0x08088405 + 1 (mod 2^32); Random(N) = (seed' * N) >> 32
      final rng = Rng(0);
      expect(rng.nextInt(100), (1 * 100) >> 32); // seed 0 → 1
      expect(rng.seed, 1);
      final rng2 = Rng(1);
      const expectedSeed = (1 * 0x08088405 + 1) & 0xFFFFFFFF;
      final roll = rng2.nextInt(1000);
      expect(rng2.seed, expectedSeed);
      expect(roll, (expectedSeed * 1000) >> 32);
    });

    test('nextInt stays in [0, n) and covers the range', () {
      final rng = Rng(42);
      final seen = <int>{};
      for (var i = 0; i < 10000; i++) {
        final v = rng.nextInt(7);
        expect(v, inInclusiveRange(0, 6));
        seen.add(v);
      }
      expect(seen, hasLength(7));
    });

    test('huge n never overflows into negative results', () {
      // Late-game treasuries exceed 2^31; the naive (roll × n) >> 32
      // overflowed 64-bit ints and returned negative numbers.
      final rng = Rng(42);
      for (final n in [1 << 31, 1 << 40, 1 << 52, (1 << 62) - 1]) {
        for (var i = 0; i < 200; i++) {
          final v = rng.nextInt(n);
          expect(v, inInclusiveRange(0, n - 1), reason: 'n = $n');
        }
      }
    });

    test('split computation matches the naive product for small n', () {
      final naive = Rng(7);
      final rng = Rng(7);
      for (var i = 0; i < 1000; i++) {
        final n = 1 + (i * 2147479) % 0x7FFFFFFF;
        // Reference: the pre-fix formula, safe here because n < 2^31.
        final seedBefore = naive.seed;
        final expected =
            (((seedBefore * 0x08088405 + 1) & 0xFFFFFFFF) * n) >> 32;
        naive.nextInt(n); // keep the reference stream advancing
        expect(rng.nextInt(n), expected, reason: 'n = $n');
      }
    });

    test('random(0) and negative n return 0 (§25)', () {
      final rng = Rng(42);
      expect(rng.nextInt(0), 0);
      expect(rng.nextInt(-5), 0);
    });

    test('nextReal stays in [0, 1)', () {
      final rng = Rng(7);
      for (var i = 0; i < 10000; i++) {
        final v = rng.nextReal();
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThan(1));
      }
    });

    test('seed survives persist/restore mid-sequence', () {
      final a = Rng(99);
      for (var i = 0; i < 17; i++) {
        a.nextInt(1000);
      }
      final restored = Rng(a.seed);
      for (var i = 0; i < 100; i++) {
        expect(restored.nextInt(1000), a.nextInt(1000));
      }
    });
  });
}
