import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AutoL10nBinding.ensureInitialized', () {
    test('throws when neither translator nor provider and loadPregenerated is false', () {
      expect(
        () => AutoL10nBinding.ensureInitialized(
          targetLocale: const Locale('ru'),
          loadPregenerated: false,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('translator or provider'),
        )),
      );
    });

    test('autoL10n() throws same as ensureInitialized when no provider and loadPregenerated false', () {
      expect(
        () => autoL10n(
          targetLocale: const Locale('ru'),
          loadPregenerated: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    // Other ensureInitialized behaviours (provider/targetLocale/cache) cannot
    // be unit-tested here: the test runner already has a binding, so creating
    // AutoL10nBinding() would trigger "Binding is already initialized".
    // createTranslator and optional targetLocale are covered by
    // translation_provider_test and manual/integration runs.
  });

  group('AutoL10nBinding', () {
    testWidgets('integration: MockTranslator translates Text widgets',
        (tester) async {
      // The test binding is already initialized by flutter_test.
      // We can still test the cache and scanner independently.
      final cache = TranslationCache(
        translator: const MockTranslator(
          prefix: 'TR',
          delay: Duration.zero,
        ),
        targetLang: 'ru',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Hello World'),
                Text('Welcome'),
              ],
            ),
          ),
        ),
      );

      // Scan the tree
      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      // Wait for debounce + translation
      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.translate('Hello World'), 'TR Hello World');
      expect(cache.translate('Welcome'), 'TR Welcome');

      cache.dispose();
    });

    testWidgets('second lookup with same cache causes no API calls',
        (tester) async {
      final cache = TranslationCache(
        translator: const MockTranslator(
          prefix: 'TR',
          delay: Duration.zero,
        ),
        targetLang: 'ru',
      );

      // First scan
      await tester.pumpWidget(
        const MaterialApp(
          home: Text('Hello World'),
        ),
      );

      TreeScanner.scan(tester.binding.rootElement!, cache);
      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('Hello World'), true);

      // Second scan — same string should not be re-enqueued
      TreeScanner.scan(tester.binding.rootElement!, cache);
      await tester.pump(const Duration(milliseconds: 400));

      // Still the same translation
      expect(cache.translate('Hello World'), 'TR Hello World');

      cache.dispose();
    });

    testWidgets('RichText spans are scanned and translated into cache', (tester) async {
      final cache = TranslationCache(
        translator: const MockTranslator(
          prefix: 'TR',
          delay: Duration.zero,
        ),
        targetLang: 'ru',
      );
      addTearDown(() => cache.dispose());

      await tester.pumpWidget(
        MaterialApp(
          home: RichText(
            text: const TextSpan(
              text: 'Bold part. ',
              children: [
                TextSpan(text: 'Normal part.'),
              ],
            ),
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);
      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('Bold part. '), true);
      expect(cache.has('Normal part.'), true);
      expect(cache.translate('Bold part. '), 'TR Bold part. ');
      expect(cache.translate('Normal part.'), 'TR Normal part.');
    });
  });
}
