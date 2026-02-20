import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createTranslator', () {
    test('mymemory returns MyMemoryTranslator', () {
      final t = createTranslator(TranslationProvider.mymemory);
      expect(t, isA<MyMemoryTranslator>());
      expect((t as MyMemoryTranslator).email, isNull);
    });

    test('mymemory with mymemoryEmail passes email', () {
      final t = createTranslator(
        TranslationProvider.mymemory,
        mymemoryEmail: 'test@example.com',
      );
      expect((t as MyMemoryTranslator).email, 'test@example.com');
    });

    test('DeepL without apiKey throws ArgumentError', () {
      expect(
        () => createTranslator(TranslationProvider.DeepL),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('apiKey'),
        )),
      );
    });

    test('DeepL with empty apiKey throws ArgumentError', () {
      expect(
        () => createTranslator(TranslationProvider.DeepL, apiKey: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('DeepL with apiKey returns DeepLTranslator', () {
      final t = createTranslator(TranslationProvider.DeepL, apiKey: 'key');
      expect(t, isA<DeepLTranslator>());
      expect((t as DeepLTranslator).apiKey, 'key');
    });

    test('google without apiKey throws ArgumentError', () {
      expect(
        () => createTranslator(TranslationProvider.google),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('apiKey'),
        )),
      );
    });

    test('google with empty apiKey throws ArgumentError', () {
      expect(
        () => createTranslator(TranslationProvider.google, apiKey: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('google with apiKey returns GoogleTranslator', () {
      final t = createTranslator(TranslationProvider.google, apiKey: 'key');
      expect(t, isA<GoogleTranslator>());
      expect((t as GoogleTranslator).apiKey, 'key');
    });

    test('lingva returns LingvaTranslator with default baseUrl', () {
      final t = createTranslator(TranslationProvider.lingva);
      expect(t, isA<LingvaTranslator>());
      expect((t as LingvaTranslator).baseUrl, 'https://lingva.ml');
    });

    test('lingva with lingvaBaseUrl uses custom url', () {
      final t = createTranslator(
        TranslationProvider.lingva,
        lingvaBaseUrl: 'https://custom.lingva',
      );
      expect((t as LingvaTranslator).baseUrl, 'https://custom.lingva');
    });

    test('mock returns MockTranslator with useLocalePrefix', () async {
      final t = createTranslator(TranslationProvider.mock);
      expect(t, isA<MockTranslator>());
      final result = await t.translateBatch(['Hi'], targetLang: 'ru');
      expect(result['Hi'], '[ru] Hi');
    });
  });
}
