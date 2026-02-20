import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../placeholder_guard.dart';
import '../translator.dart';

/// Translator that uses the DeepL API.
///
/// Auto-detects free vs pro endpoint by checking for the `:fx` suffix
/// on the API key.
class DeepLTranslator implements AbstractTranslator {
  final String apiKey;

  const DeepLTranslator({required this.apiKey});

  String get _baseUrl => apiKey.endsWith(':fx')
      ? 'https://api-free.deepl.com/v2'
      : 'https://api.deepl.com/v2';

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    final results = <String, String>{};

    // Protect placeholders before sending
    final protected = <String, (String, List<String>)>{};
    for (final text in texts) {
      protected[text] = PlaceholderGuard.protect(text);
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/translate'),
        headers: {
          'Authorization': 'DeepL-Auth-Key $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': protected.values.map((e) => e.$1).toList(),
          'target_lang': targetLang.toUpperCase(),
          'source_lang': sourceLang.toUpperCase(),
          'tag_handling': 'xml',
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final translations = json['translations'] as List;

        var i = 0;
        for (final original in texts) {
          if (i < translations.length) {
            final translatedText = translations[i]['text'] as String;
            final (_, placeholders) = protected[original]!;
            results[original] =
                PlaceholderGuard.restore(translatedText, placeholders);
          } else {
            results[original] = original;
          }
          i++;
        }
      } else {
        debugPrint(
          '[auto_l10n] DeepL error ${response.statusCode}: ${response.body}',
        );
        for (final text in texts) {
          results[text] = text;
        }
      }
    } catch (e) {
      debugPrint('[auto_l10n] DeepL request failed: $e');
      for (final text in texts) {
        results[text] = text;
      }
    }

    return results;
  }
}
