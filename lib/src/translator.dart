/// Interface for all translation backends.
///
/// Implement this to provide your own translation service.
abstract class AbstractTranslator {
  /// Translates a batch of strings.
  ///
  /// Returns `Map<original, translated>`.
  /// Implementations should throw on API/network errors so that
  /// [TranslationCache] can re-queue the batch and retry with backoff.
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  });
}
