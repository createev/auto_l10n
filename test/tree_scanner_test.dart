import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TreeScanner', () {
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

    testWidgets('finds Text widgets in a widget tree', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('Hello World'),
              Text('Another text'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      // Wait for debounce + flush
      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('Hello World'), true);
      expect(cache.has('Another text'), true);
    });

    testWidgets('skips strings shorter than 2 chars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('A'),
              Text('OK text here'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('A'), false);
      expect(cache.has('OK text here'), true);
    });

    testWidgets('skips digit-only strings', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('12345'),
              Text('\$99.99'),
              Text('Real text here'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('12345'), false);
      expect(cache.has('\$99.99'), false);
      expect(cache.has('Real text here'), true);
    });

    testWidgets('skips long strings with no spaces', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('abcdefghijklmnopqrstuvwxyz1234'),
              Text('Normal sentence here'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('abcdefghijklmnopqrstuvwxyz1234'), false);
      expect(cache.has('Normal sentence here'), true);
    });

    testWidgets('recurses into nested widgets', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Deeply nested text'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('Deeply nested text'), true);
    });
  });
}
