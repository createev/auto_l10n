import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../placeholder_guard.dart';
import '../translator.dart';

/// Translator that uses the Google Cloud Translation API v2.
class GoogleTranslator implements AbstractTranslator {
  final String apiKey;

  const GoogleTranslator({required this.apiKey});

  static const _baseUrl =
      'https://translation.googleapis.com/language/translate/v2';

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
        Uri.parse('$_baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': protected.values.map((e) => e.$1).toList(),
          'target': targetLang,
          'source': sourceLang,
          'format': 'text',
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        final translations = data['translations'] as List;

        var i = 0;
        for (final original in texts) {
          if (i < translations.length) {
            final translatedText =
                translations[i]['translatedText'] as String;
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
          '[auto_l10n] Google Translate error ${response.statusCode}: '
          '${response.body}',
        );
        for (final text in texts) {
          results[text] = text;
        }
      }
    } catch (e) {
      debugPrint('[auto_l10n] Google Translate request failed: $e');
      for (final text in texts) {
        results[text] = text;
      }
    }

    return results;
  }
}
