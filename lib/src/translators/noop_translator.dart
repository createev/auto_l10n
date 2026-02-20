import '../translator.dart';

/// Translator that returns the original strings unchanged.
/// Used when only pre-generated ARB is loaded (no API).
class NoOpTranslator implements AbstractTranslator {
  const NoOpTranslator();

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async =>
      {for (final t in texts) t: t};
}
