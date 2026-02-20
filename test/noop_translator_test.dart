import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoOpTranslator', () {
    test('translateBatch returns originals unchanged', () async {
      const translator = NoOpTranslator();

      final result = await translator.translateBatch(
        ['Hello', 'World', 'Foo bar'],
        targetLang: 'ru',
        sourceLang: 'en',
      );

      expect(result, {
        'Hello': 'Hello',
        'World': 'World',
        'Foo bar': 'Foo bar',
      });
    });

    test('empty input returns empty map', () async {
      const translator = NoOpTranslator();

      final result = await translator.translateBatch([], targetLang: 'de');

      expect(result, isEmpty);
    });
  });
}
