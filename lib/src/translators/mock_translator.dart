import '../translator.dart';

/// A translator that requires no API key and no network.
///
/// When [useLocalePrefix] is `true` (default), the target language code
/// is used as the prefix, e.g. `[ru] Hello`. Otherwise [prefix] is used.
/// Useful for demos, tests, and verifying that the translation pipeline
/// works end-to-end.
class MockTranslator implements AbstractTranslator {
  /// Static prefix added to each translated string.
  /// Ignored when [useLocalePrefix] is `true`.
  final String prefix;

  /// If `true`, uses the target language code as prefix instead of [prefix].
  final bool useLocalePrefix;

  /// Simulated network delay.
  final Duration delay;

  const MockTranslator({
    this.prefix = '\u{1F30D}',
    this.useLocalePrefix = false,
    this.delay = const Duration(milliseconds: 500),
  });

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    await Future.delayed(delay);
    final p = useLocalePrefix ? '[$targetLang]' : prefix;
    return {for (final t in texts) t: '$p $t'};
  }
}
