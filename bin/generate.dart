import 'dart:convert';
import 'dart:io';

import 'package:auto_l10n/src/placeholder_guard.dart';
import 'package:auto_l10n/src/translator.dart';
import 'package:auto_l10n/src/translators/deepl_translator.dart';
import 'package:auto_l10n/src/translators/google_translator.dart';

/// CLI tool for Mode 2: Static ARB Generation.
///
/// Usage:
/// ```
/// dart run auto_l10n:generate \
///   --api-key=YOUR_KEY \
///   --source=lib/l10n/app_en.arb \
///   --targets=ru,de,fr,ja,es \
///   --service=deepl
/// ```
void main(List<String> args) async {
  final parsed = _parseArgs(args);

  final source = parsed['source'];
  final targets = parsed['targets'];
  final apiKey = parsed['api-key'];
  final service = parsed['service'] ?? 'deepl';
  final force = parsed.containsKey('force');

  if (source == null || targets == null || apiKey == null) {
    stderr.writeln('Usage: dart run auto_l10n:generate \\');
    stderr.writeln('  --api-key=YOUR_KEY \\');
    stderr.writeln('  --source=lib/l10n/app_en.arb \\');
    stderr.writeln('  --targets=ru,de,fr \\');
    stderr.writeln('  --service=deepl|google \\');
    stderr.writeln('  --force');
    exit(1);
  }

  final sourceFile = File(source);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Error: Source file not found: $source');
    exit(1);
  }

  final sourceArb =
      jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;

  // Extract translatable keys (skip @ metadata keys)
  final translatableEntries = <String, String>{};
  for (final entry in sourceArb.entries) {
    if (entry.key.startsWith('@') || entry.key.startsWith('@@')) continue;
    if (entry.value is String) {
      translatableEntries[entry.key] = entry.value as String;
    }
  }

  if (translatableEntries.isEmpty) {
    stderr.writeln('No translatable keys found in $source');
    exit(1);
  }

  stdout.writeln('Found ${translatableEntries.length} translatable keys.');

  final translator = _createTranslator(service, apiKey);
  final targetLocales = targets.split(',').map((s) => s.trim()).toList();
  final sourceDir = sourceFile.parent.path;
  final sourceBaseName =
      sourceFile.uri.pathSegments.last.replaceAll(RegExp(r'_\w+\.arb$'), '');

  for (final locale in targetLocales) {
    stdout.writeln('Translating to $locale...');

    final targetFile = File('$sourceDir/${sourceBaseName}_$locale.arb');
    Map<String, dynamic> existingArb = {};

    if (targetFile.existsSync()) {
      existingArb =
          jsonDecode(targetFile.readAsStringSync()) as Map<String, dynamic>;
    }

    // Determine which keys need translation
    final toTranslate = <String, String>{};
    for (final entry in translatableEntries.entries) {
      if (force || !existingArb.containsKey(entry.key)) {
        toTranslate[entry.key] = entry.value;
      }
    }

    if (toTranslate.isEmpty) {
      stdout.writeln('  All keys already translated. Use --force to redo.');
      continue;
    }

    stdout.writeln('  Translating ${toTranslate.length} keys...');

    // Protect placeholders
    final protectedMap = <String, (String, List<String>)>{};
    for (final entry in toTranslate.entries) {
      protectedMap[entry.key] = PlaceholderGuard.protect(entry.value);
    }

    try {
      final results = await translator.translateBatch(
        protectedMap.values.map((e) => e.$1).toList(),
        targetLang: locale,
      );

      // Build output ARB
      final outputArb = Map<String, dynamic>.from(existingArb);
      outputArb['@@locale'] = locale;

      for (final key in toTranslate.keys) {
        final protectedText = protectedMap[key]!.$1;
        final placeholders = protectedMap[key]!.$2;
        final translated = results[protectedText] ?? protectedText;
        outputArb[key] = PlaceholderGuard.restore(translated, placeholders);

        // Copy metadata from source if exists
        final metaKey = '@$key';
        if (sourceArb.containsKey(metaKey) &&
            !outputArb.containsKey(metaKey)) {
          outputArb[metaKey] = sourceArb[metaKey];
        }
      }

      const encoder = JsonEncoder.withIndent('  ');
      targetFile.writeAsStringSync('${encoder.convert(outputArb)}\n');
      stdout.writeln('  Wrote ${targetFile.path}');
    } catch (e) {
      stderr.writeln('  Error translating to $locale: $e');
    }
  }

  stdout.writeln('Done.');
}

AbstractTranslator _createTranslator(String service, String apiKey) {
  switch (service) {
    case 'google':
      return GoogleTranslator(apiKey: apiKey);
    case 'deepl':
    default:
      return DeepLTranslator(apiKey: apiKey);
  }
}

Map<String, String?> _parseArgs(List<String> args) {
  final result = <String, String?>{};
  for (final arg in args) {
    if (arg.startsWith('--')) {
      final stripped = arg.substring(2);
      final eqIndex = stripped.indexOf('=');
      if (eqIndex == -1) {
        result[stripped] = null;
      } else {
        result[stripped.substring(0, eqIndex)] = stripped.substring(eqIndex + 1);
      }
    }
  }
  return result;
}
