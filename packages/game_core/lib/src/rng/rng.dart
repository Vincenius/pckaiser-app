/// Injectable, seeded RNG (ORIGINAL_GAME.md §25).
///
/// Implements the Borland Pascal LCG used by the original game so that
/// results are deterministic and identical on every platform (Dart VM and
/// web), independent of `dart:math`'s unspecified algorithm:
///
///   seed := seed * $08088405 + 1   (mod 2^32)
///   Random(N) = high 32 bits of seed * N
///
/// The seed is part of the game state, which makes saves replayable and the
/// server able to reproduce/validate outcomes.
class Rng {
  Rng(int seed) : _seed = seed & _mask32;

  static const int _multiplier = 0x08088405;
  static const int _mask32 = 0xFFFFFFFF;

  int _seed;

  /// Current seed; persist this in the game state after use.
  int get seed => _seed;

  int _next() {
    _seed = (_seed * _multiplier + 1) & _mask32;
    return _seed;
  }

  /// `random(N)` → uniform integer in `[0, n-1]`; `random(0)` = 0 (§25).
  int nextInt(int n) {
    if (n <= 0) return 0;
    return (_next() * n) >> 32;
  }

  /// `RandomReal` → uniform double in `[0, 1)`.
  double nextReal() => _next() / 4294967296.0;
}
