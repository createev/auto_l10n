import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranslationCache', () {
    late TranslationCache cache;

    setUp(() {
      cache = TranslationCache(
        translator: const MockTranslator(
          prefix: 'TR',
          delay: Duration.zero,
        ),
        targetLang: 'ru',
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('translate returns original before translation', () {
      expect(cache.translate('Hello'), 'Hello');
    });

    test('has returns false before translation', () {
      expect(cache.has('Hello'), false);
    });

    test('enqueue collects strings and debounces 300ms', () async {
      cache.enqueue('Hello');
      cache.enqueue('World');

      // Not yet translated (debounce hasn't fired)
      expect(cache.has('Hello'), false);

      // Wait for debounce + flush
      await Future.delayed(const Duration(milliseconds: 400));

      expect(cache.has('Hello'), true);
      expect(cache.has('World'), true);
    });

    test('translate returns translated text after flush', () async {
      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(cache.translate('Hello'), 'TR Hello');
    });

    test('duplicate enqueues are ignored', () async {
      cache.enqueue('Hello');
      cache.enqueue('Hello');
      cache.enqueue('Hello');

      await Future.delayed(const Duration(milliseconds: 400));

      expect(cache.translate('Hello'), 'TR Hello');
    });

    test('already-cached strings are not re-enqueued', () async {
      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(cache.has('Hello'), true);

      // Enqueue again — should be a no-op
      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));

      // Still the same translation
      expect(cache.translate('Hello'), 'TR Hello');
    });

    test('hasNewTranslations flag is set after flush', () async {
      expect(cache.hasNewTranslations, false);

      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(cache.hasNewTranslations, true);
    });

    test('notifies listeners when translations arrive', () async {
      var notified = false;
      cache.addListener(() => notified = true);

      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(notified, true);
    });
  });
}
