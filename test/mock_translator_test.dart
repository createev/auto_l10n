import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockTranslator', () {
    test('translateBatch returns prefixed strings', () async {
      const translator = MockTranslator(
        prefix: 'TEST',
        delay: Duration.zero,
      );

      final result = await translator.translateBatch(
        ['Hello', 'World'],
        targetLang: 'ru',
      );

      expect(result, {
        'Hello': 'TEST Hello',
        'World': 'TEST World',
      });
    });

    test('prefix is applied to all strings', () async {
      const translator = MockTranslator(
        prefix: '>>',
        delay: Duration.zero,
      );

      final result = await translator.translateBatch(
        ['One', 'Two', 'Three'],
        targetLang: 'de',
      );

      for (final entry in result.entries) {
        expect(entry.value, startsWith('>> '));
      }
    });

    test('delay is respected', () async {
      const translator = MockTranslator(
        delay: Duration(milliseconds: 100),
      );

      final sw = Stopwatch()..start();
      await translator.translateBatch(['test'], targetLang: 'fr');
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
    });

    test('empty input returns empty map', () async {
      const translator = MockTranslator(delay: Duration.zero);

      final result = await translator.translateBatch([], targetLang: 'ru');

      expect(result, isEmpty);
    });
  });
}
