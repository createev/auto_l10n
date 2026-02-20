/// Interface for all translation backends.
///
/// Implement this to provide your own translation service.
abstract class AbstractTranslator {
  /// Translates a batch of strings.
  ///
  /// Returns `Map<original, translated>`.
  /// Must not throw — return the original string on error.
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  });
}
