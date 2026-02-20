import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../placeholder_guard.dart';
import '../translator.dart';

/// Free translator powered by MyMemory API.
///
/// No API key required. 5,000 words/day anonymous, 50,000/day with email.
///
/// ```dart
/// AutoL10nBinding.ensureInitialized(
///   translator: const MyMemoryTranslator(),
///   targetLocale: const Locale('ru'),
/// );
/// ```
class MyMemoryTranslator implements AbstractTranslator {
  /// Optional email to increase daily limit from 5,000 to 50,000 words.
  final String? email;

  const MyMemoryTranslator({this.email});

  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    final results = <String, String>{};

    final futures = <String, Future<String>>{};
    for (final text in texts) {
      futures[text] = _translateOne(text, targetLang, sourceLang);
    }

    for (final entry in futures.entries) {
      try {
        results[entry.key] = await entry.value;
      } catch (e) {
        debugPrint('[auto_l10n] MyMemory error for "${entry.key}": $e');
        results[entry.key] = entry.key;
      }
    }

    return results;
  }

  /// Maps Flutter/BCP 47 language codes to MyMemory API codes.
  /// MyMemory uses ISO/RFC3066; only codes that differ from [lang] are listed.
  /// See https://mymemory.translated.net/doc/spec.php and supported language lists.
  static const Map<String, String> _langForApiMap = {
    'zh': 'zh-CN', // bare "zh" not supported; default to simplified
  };

  static String _langForApi(String lang) => _langForApiMap[lang] ?? lang;

  Future<String> _translateOne(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    final (protectedText, placeholders) = PlaceholderGuard.protect(text);
    final apiTarget = _langForApi(targetLang);
    final apiSource = _langForApi(sourceLang);

    try {
      final params = {
        'q': protectedText,
        'langpair': '$apiSource|$apiTarget',
      };
      if (email != null) {
        params['de'] = email!;
      }

      final uri = Uri.https(
        'api.mymemory.translated.net',
        '/get',
        params,
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['responseData'] as Map<String, dynamic>;
        final translated = data['translatedText'] as String;
        return PlaceholderGuard.restore(translated, placeholders);
      } else {
        debugPrint(
          '[auto_l10n] MyMemory ${response.statusCode}: ${response.body}',
        );
        return text;
      }
    } catch (e) {
      debugPrint('[auto_l10n] MyMemory request failed: $e');
      return text;
    }
  }
}
