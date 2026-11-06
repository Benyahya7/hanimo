import 'package:animeapp/core/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('Ok carries its value', () {
      const r = Result.ok(42);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 42);
      expect(r.errorOrNull, isNull);
    });

    test('Err carries a readable message', () {
      const r = Result<int>.err('Animeify did not answer.');
      expect(r.isErr, isTrue);
      expect(r.isOk, isFalse);
      expect(r.errorOrNull, 'Animeify did not answer.');
      expect(r.valueOrNull, isNull);
    });
  });
}
