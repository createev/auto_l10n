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
  static final RegExp _placeholderTag = RegExp(r'<x id="ph_\d+"/>');

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
      final (protectedText, placeholders) = PlaceholderGuard.protect(text);
      protected[text] = (_escapeXmlExceptPlaceholders(protectedText), placeholders);
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
            final restored = PlaceholderGuard.restore(
              translatedText,
              placeholders,
            );
            results[original] = _decodeXmlEntities(restored);
          } else {
            results[original] = original;
          }
          i++;
        }
      } else {
        final body = response.body.length > 300
            ? '${response.body.substring(0, 300)}...'
            : response.body;
        debugPrint(
          '[auto_l10n] DeepL error ${response.statusCode}: $body',
        );
        throw StateError(
          'DeepL request failed with status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[auto_l10n] DeepL request failed: $e');
      rethrow;
    }

    return results;
  }

  static String _escapeXmlExceptPlaceholders(String input) {
    final out = StringBuffer();
    var index = 0;
    for (final m in _placeholderTag.allMatches(input)) {
      if (m.start > index) {
        out.write(_escapeXml(input.substring(index, m.start)));
      }
      out.write(m.group(0)!);
      index = m.end;
    }
    if (index < input.length) {
      out.write(_escapeXml(input.substring(index)));
    }
    return out.toString();
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _decodeXmlEntities(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
