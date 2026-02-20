import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../placeholder_guard.dart';
import '../translator.dart';

/// Free translator powered by Lingva Translate (Google Translate frontend).
///
/// No API key, no registration. Uses public Lingva instances.
///
/// ```dart
/// AutoL10nBinding.ensureInitialized(
///   translator: const LingvaTranslator(),
///   targetLocale: const Locale('ru'),
/// );
/// ```
class LingvaTranslator implements AbstractTranslator {
  /// Base URL of the Lingva instance.
  final String baseUrl;

  const LingvaTranslator({
    this.baseUrl = 'https://lingva.ml',
  });

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    final results = <String, String>{};

    // Lingva translates one string at a time — fire in parallel.
    final futures = <String, Future<String>>{};
    for (final text in texts) {
      futures[text] = _translateOne(text, targetLang, sourceLang);
    }

    for (final entry in futures.entries) {
      try {
        results[entry.key] = await entry.value;
      } catch (e) {
        debugPrint('[auto_l10n] Lingva error for "${entry.key}": $e');
        results[entry.key] = entry.key;
      }
    }

    return results;
  }

  Future<String> _translateOne(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    final (protectedText, placeholders) = PlaceholderGuard.protect(text);

    try {
      final encoded = Uri.encodeComponent(protectedText);
      final url = '$baseUrl/api/v1/$sourceLang/$targetLang/$encoded';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final translated = json['translation'] as String;
        return PlaceholderGuard.restore(translated, placeholders);
      } else {
        debugPrint(
          '[auto_l10n] Lingva ${response.statusCode}: ${response.body}',
        );
        return text;
      }
    } catch (e) {
      debugPrint('[auto_l10n] Lingva request failed: $e');
      return text;
    }
  }
}
