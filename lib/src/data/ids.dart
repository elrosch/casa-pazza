import 'dart:math';

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _random = Random.secure();

/// Generates a PocketBase-compatible record id (15 chars, a-z0-9), so records
/// can be created offline and pushed later under the same id.
String newRecordId() => List.generate(
  15,
  (_) => _alphabet[_random.nextInt(_alphabet.length)],
).join();
