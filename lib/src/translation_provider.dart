import 'translator.dart';
import 'translators/deepl_translator.dart';
import 'translators/google_translator.dart';
import 'translators/lingva_translator.dart';
import 'translators/mock_translator.dart';
import 'translators/mymemory_translator.dart';

/// Built-in translation backends for [AutoL10nBinding.ensureInitialized].
///
/// Use [provider] + optional [apiKey] for a simple setup, or pass a
/// custom [AbstractTranslator] to [ensureInitialized] for full control.
enum TranslationProvider {
  /// MyMemory (free, no API key; optional email for higher limit).
  mymemory,

  /// DeepL (requires [apiKey]).
  DeepL,

  /// Google Cloud Translation API v2 (requires [apiKey]).
  google,

  /// Lingva (free, no API key; public instances).
  lingva,

  /// Mock: prefixes text with `[langCode]` for demos/tests.
  mock,
}

/// Creates an [AbstractTranslator] for the given [provider].
///
/// [apiKey] is required for [TranslationProvider.DeepL] and
/// [TranslationProvider.google]. Optional [mymemoryEmail] increases
/// MyMemory daily limit. Optional [lingvaBaseUrl] overrides Lingva instance.
///
/// For a custom backend, implement [AbstractTranslator] and pass it
/// directly to [AutoL10nBinding.ensureInitialized].
AbstractTranslator createTranslator(
  TranslationProvider provider, {
  String? apiKey,
  String? mymemoryEmail,
  String? lingvaBaseUrl,
}) {
  switch (provider) {
    case TranslationProvider.mymemory:
      return MyMemoryTranslator(email: mymemoryEmail);
    case TranslationProvider.DeepL:
      if (apiKey == null || apiKey.isEmpty) {
        throw ArgumentError('apiKey is required for TranslationProvider.DeepL');
      }
      return DeepLTranslator(apiKey: apiKey);
    case TranslationProvider.google:
      if (apiKey == null || apiKey.isEmpty) {
        throw ArgumentError('apiKey is required for TranslationProvider.google');
      }
      return GoogleTranslator(apiKey: apiKey);
    case TranslationProvider.lingva:
      return LingvaTranslator(
        baseUrl: lingvaBaseUrl ?? 'https://lingva.ml',
      );
    case TranslationProvider.mock:
      return const MockTranslator(useLocalePrefix: true);
  }
}
