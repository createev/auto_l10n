import 'package:auto_l10n/auto_l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

/// Translator that throws on first call, then returns prefixed text.
class _ThrowingOnceTranslator implements AbstractTranslator {
  bool _thrown = false;

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    if (!_thrown) {
      _thrown = true;
      throw Exception('API error');
    }
    return {for (final t in texts) t: 'OK $t'};
  }
}

/// Translator that returns empty map (simulates partial failure).
class _EmptyResultTranslator implements AbstractTranslator {
  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async =>
      {};
}

/// Translator that always throws and counts attempts.
class _AlwaysThrowTranslator implements AbstractTranslator {
  int calls = 0;

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    calls++;
    throw Exception('always fail');
  }
}

class _IdentityTranslator implements AbstractTranslator {
  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async =>
      {for (final t in texts) t: t};
}

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

    test('trimmed cache key still translates text with outer whitespace', () {
      final preloaded = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
        preloaded: {'Hello': 'Привет'},
      );
      addTearDown(() => preloaded.dispose());

      expect(preloaded.has(' Hello '), true);
      expect(preloaded.translate(' Hello '), ' Привет ');
    });

    test(
        'trimmed translation wins when direct key exists but equals original',
        () {
      final preloaded = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
        preloaded: {
          'Stop guessing. Start ': 'Stop guessing. Start ',
          'Stop guessing. Start': 'Хватит гадать. Начните',
        },
      );
      addTearDown(() => preloaded.dispose());

      expect(preloaded.translate('Stop guessing. Start '),
          'Хватит гадать. Начните ');
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

    test('when translator throws, batch is retried and eventually translated',
        () async {
      final badCache = TranslationCache(
        translator: _ThrowingOnceTranslator(),
        targetLang: 'ru',
      );
      addTearDown(() => badCache.dispose());

      badCache.enqueue('Hi');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(badCache.has('Hi'), false);
      expect(badCache.translate('Hi'), 'Hi');

      // Retry is scheduled with backoff (first retry ~= 1s).
      await Future.delayed(const Duration(milliseconds: 1200));
      expect(badCache.has('Hi'), true);
      expect(badCache.translate('Hi'), 'OK Hi');
    });

    test('when translator returns empty map, originals are shown and no crash',
        () async {
      final emptyCache = TranslationCache(
        translator: _EmptyResultTranslator(),
        targetLang: 'ru',
      );
      addTearDown(() => emptyCache.dispose());

      emptyCache.enqueue('Foo');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(emptyCache.has('Foo'), false);
      expect(emptyCache.translate('Foo'), 'Foo');
    });

    test('unchanged translations are not stored in cache', () async {
      final idCache = TranslationCache(
        translator: _IdentityTranslator(),
        targetLang: 'ru',
      );
      addTearDown(() => idCache.dispose());

      idCache.enqueue('Same');
      await Future.delayed(const Duration(milliseconds: 400));

      expect(idCache.has('Same'), false);
      expect(idCache.translate('Same'), 'Same');
    });

    test('stops auto-retrying after max attempts, resumes on new enqueue',
        () async {
      final throwingTranslator = _AlwaysThrowTranslator();
      final badCache = TranslationCache(
        translator: throwingTranslator,
        targetLang: 'ru',
      );
      addTearDown(() => badCache.dispose());

      badCache.enqueue('Hi');

      // Initial flush (~300ms) + retries at 1s, 2s, 3s.
      await Future.delayed(const Duration(milliseconds: 7000));
      expect(throwingTranslator.calls, 4);

      // No more automatic retries after give-up.
      await Future.delayed(const Duration(milliseconds: 3500));
      expect(throwingTranslator.calls, 4);

      // New strings unlock retries again (new batch path).
      badCache.enqueue('Again');
      await Future.delayed(const Duration(milliseconds: 400));
      expect(throwingTranslator.calls, 5);
    });

    test('clearInMemory allows re-enqueue and translation again', () async {
      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));
      expect(cache.has('Hello'), true);

      cache.clearInMemory();
      expect(cache.has('Hello'), false);
      expect(cache.translate('Hello'), 'Hello');

      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));
      expect(cache.has('Hello'), true);
      expect(cache.translate('Hello'), 'TR Hello');
    });
  });

  group('TranslationCache with preloaded', () {
    test('preloaded strings are in cache immediately', () {
      final cache = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
        preloaded: {'Hello': 'Привет', 'World': 'Мир'},
      );
      addTearDown(() => cache.dispose());

      expect(cache.has('Hello'), true);
      expect(cache.has('World'), true);
      expect(cache.translate('Hello'), 'Привет');
      expect(cache.translate('World'), 'Мир');
    });

    test('addPreloaded merges into cache and notifies', () async {
      final cache = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
      );
      addTearDown(() => cache.dispose());

      var notified = false;
      cache.addListener(() => notified = true);
      cache.addPreloaded({'Foo': 'Фу'});

      expect(cache.has('Foo'), true);
      expect(cache.translate('Foo'), 'Фу');
      expect(notified, true);
    });

    test(
        'addPreloaded with empty map does not notify and does not change cache',
        () {
      final cache = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
      );
      addTearDown(() => cache.dispose());

      var notified = false;
      cache.addListener(() => notified = true);
      cache.addPreloaded({});

      expect(notified, false);
      expect(cache.has('Any'), false);
    });
  });

  group('TranslationCache loadFromPrefs', () {
    test('prefs values do not override preloaded translations', () async {
      SharedPreferences.setMockInitialValues({
        'auto_l10n_ru': '{"Hello":"Hello"}',
      });
      final cache = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
        preloaded: {'Hello': 'Привет'},
      );
      addTearDown(() => cache.dispose());

      await cache.loadFromPrefs();
      expect(cache.translate('Hello'), 'Привет');
    });

    test('invalid JSON in prefs does not throw; cache still works', () async {
      SharedPreferences.setMockInitialValues({
        'auto_l10n_ru': 'not valid json',
      });
      final cache = TranslationCache(
        translator: const MockTranslator(prefix: 'TR', delay: Duration.zero),
        targetLang: 'ru',
      );
      addTearDown(() => cache.dispose());

      await cache.loadFromPrefs();
      expect(cache.has('Hello'), false);

      cache.enqueue('Hello');
      await Future.delayed(const Duration(milliseconds: 400));
      expect(cache.has('Hello'), true);
      expect(cache.translate('Hello'), 'TR Hello');
    });

  });
}
