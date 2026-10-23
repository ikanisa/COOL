import 'dart:math';

class PublicIdGenerator {
  PublicIdGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  String generate(Set<String> existing) {
    for (var attempt = 0; attempt < 64; attempt++) {
      final value = _random.nextInt(1000000).toString().padLeft(6, '0');
      if (!existing.contains(value)) return value;
    }
    throw StateError('Unable to allocate a unique public ID');
  }
}
