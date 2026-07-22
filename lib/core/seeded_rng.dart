/// Shared deterministic PRNG for the league + siege engines.
///
/// 32-bit xorshift using ONLY shift/xor arithmetic masked to 32 bits, so it is
/// **bit-identical on web (JS) and native**. Every device computes the same
/// AI league / siege from the same seed — never use Random() or wall-clock in
/// engine code.
class SeededRng {
  int _s;
  SeededRng(int seed) : _s = (seed == 0 ? 0x9E3779B9 : (seed & 0xFFFFFFFF));

  int next() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x & 0xFFFFFFFF;
    return _s;
  }

  double unit() => next() / 4294967296.0; // [0,1)
  double range(double a, double b) => a + (b - a) * unit();

  int intRange(int a, int bExclusive) {
    final span = bExclusive - a;
    if (span <= 0) return a;
    return a + (next() % span);
  }
}

/// Shift/xor hash of the seed parts (no large multiply → web-safe determinism).
int seedFromParts(List<Object> parts) {
  var h = 0x9E3779B9;
  for (final part in parts) {
    final s = part.toString();
    for (final c in s.codeUnits) {
      h = (h ^ c) & 0xFFFFFFFF;
      h ^= (h << 13) & 0xFFFFFFFF;
      h ^= h >> 7;
      h ^= (h << 17) & 0xFFFFFFFF;
    }
    h = (h ^ 0x7C) & 0xFFFFFFFF; // field separator
  }
  return h & 0xFFFFFFFF;
}
