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

    testWidgets('extracts text from RichText with nested TextSpans', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RichText(
            text: const TextSpan(
              text: 'First part. ',
              children: [
                TextSpan(text: 'Second part. '),
                TextSpan(
                  text: 'Third part.',
                  children: [
                    TextSpan(text: 'Innermost text.'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('First part. '), true);
      expect(cache.has('Second part. '), true);
      expect(cache.has('Third part.'), true);
      expect(cache.has('Innermost text.'), true);
    });

    testWidgets('does not skip string with length 2 (boundary)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('Ab'),
              Text('OK'),
              Text('X'),
              Text('Real sentence'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('Ab'), true);
      expect(cache.has('OK'), true);
      expect(cache.has('X'), false);
      expect(cache.has('Real sentence'), true);
    });

    testWidgets('skips whitespace-only string', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('   '),
              Text('  \t  '),
              Text('Good text'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('   '), false);
      expect(cache.has('  \t  '), false);
      expect(cache.has('Good text'), true);
    });

    testWidgets('skips long string with no spaces (>25 chars)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              Text('abcdefghijklmnopqrstuvwxyz'),
              Text('A long sentence with spaces is translated'),
            ],
          ),
        ),
      );

      final rootElement = tester.binding.rootElement!;
      TreeScanner.scan(rootElement, cache);

      await tester.pump(const Duration(milliseconds: 400));

      expect(cache.has('abcdefghijklmnopqrstuvwxyz'), false);
      expect(cache.has('A long sentence with spaces is translated'), true);
    });
  });
}
