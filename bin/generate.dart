import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:http/http.dart' as http;

/// Default target locales when --service is set and --target-langs is omitted.
const List<String> defaultTargetLangs = [
  'es',
  'de',
  'fr',
  'pt',
  'ru',
  'zh',
  'ja',
];

/// CLI: generate ARB from code or from existing ARB. Run: dart run auto_l10n
void main(List<String> args) async {
  final parsed = _parseArgs(args);
  final from = parsed['from'] ?? 'code';
  final force = parsed.containsKey('force');
  final service = parsed['service'];
  final apiKey = parsed['api-key'];
  final sourceLang = parsed['source-lang'] ?? 'en';
  final outputPath = parsed['output-path'] ?? 'assets/auto_l10n';
  final targetLangsRaw = parsed['target-langs'];
  final targetLangs = targetLangsRaw != null && targetLangsRaw.isNotEmpty
      ? targetLangsRaw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList()
      : (service != null ? defaultTargetLangs : <String>[]);

  if (from == 'arb') {
    await _runFromArb(
      parsed: parsed,
      sourceLang: sourceLang,
      outputPath: outputPath,
      targetLangs: targetLangs,
      service: service,
      apiKey: apiKey,
      force: force,
    );
  } else {
    await _runFromCode(
      parsed: parsed,
      sourceLang: sourceLang,
      outputPath: outputPath,
      targetLangs: targetLangs,
      service: service,
      apiKey: apiKey,
      force: force,
    );
  }
  stdout.writeln('Done.');
}

Future<void> _runFromCode({
  required Map<String, String?> parsed,
  required String sourceLang,
  required String outputPath,
  required List<String> targetLangs,
  required String? service,
  required String? apiKey,
  required bool force,
}) async {
  final inputPath = parsed['input-path'] ?? 'lib';
  final codeDir = Directory(inputPath);
  if (!codeDir.existsSync()) {
    stderr.writeln('Error: Code directory not found: $inputPath');
    exit(1);
  }

  final strings = _scanDartStrings(codeDir);
  if (strings.isEmpty) {
    stdout.writeln('No string literals found in Text widgets under $inputPath');
    return;
  }
  stdout.writeln('Found ${strings.length} unique strings in code.');

  final outDir = Directory(outputPath);
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final sourceArbPath = '$outputPath/app_$sourceLang.arb';
  final sourceArb = _loadOrCreateArb(sourceArbPath);

  // Merge: add new keys from code; if force, overwrite existing key values
  var added = 0;
  for (final s in strings) {
    if (force || !sourceArb.containsKey(s)) {
      sourceArb[s] = s;
      added++;
    }
  }
  sourceArb['@@locale'] = sourceLang;
  _writeArb(sourceArbPath, sourceArb);
  if (added > 0)
    stdout.writeln('Wrote $sourceArbPath (${added} keys updated).');

  if (service == null || service.isEmpty) return;

  if (apiKey == null || apiKey.isEmpty) {
    if (service == 'deepl' || service == 'google') {
      stderr.writeln('Error: --api-key is required for --service=$service');
      exit(1);
    }
  }

  final translator = _createCliTranslator(
    service,
    apiKey: apiKey,
    email: parsed['email'],
    baseUrl: parsed['base-url'],
  );
  final sourceStrings = sourceArb.entries
      .where((e) => !e.key.startsWith('@') && e.value is String)
      .map((e) => MapEntry(e.key, e.value as String))
      .toList();

  for (final locale in targetLangs) {
    if (locale == sourceLang) continue;
    stdout.writeln('Translating to $locale...');
    final targetPath = '$outputPath/app_$locale.arb';
    final existing = _loadOrCreateArb(targetPath);
    final toTranslate = <String, String>{};
    for (final e in sourceStrings) {
      if (force || !existing.containsKey(e.key)) toTranslate[e.key] = e.value;
    }
    if (toTranslate.isEmpty) {
      stdout.writeln('  All keys present. Use --force to redo.');
      continue;
    }
    try {
      final protected = <String, (String, List<String>)>{};
      for (final e in toTranslate.entries) {
        protected[e.key] = _cliPlaceholderProtect(e.value);
      }
      final results = await translator(
        protected.values.map((x) => x.$1).toList(),
        targetLang: locale,
        sourceLang: sourceLang,
      );
      existing['@@locale'] = locale;
      for (final key in toTranslate.keys) {
        final (protectedText, placeholders) = protected[key]!;
        final translated = results[protectedText] ?? toTranslate[key]!;
        existing[key] = _cliPlaceholderRestore(translated, placeholders);
      }
      _writeArb(targetPath, existing);
      stdout.writeln('  Wrote $targetPath');
    } catch (e) {
      stderr.writeln('  Error: $e');
    }
  }
}

Future<void> _runFromArb({
  required Map<String, String?> parsed,
  required String sourceLang,
  required String outputPath,
  required List<String> targetLangs,
  required String? service,
  required String? apiKey,
  required bool force,
}) async {
  final inputPath = parsed['input-path'] ?? 'l10n/app_$sourceLang.arb';
  final sourceFile = File(inputPath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Error: Source ARB not found: $inputPath');
    exit(1);
  }

  final sourceArb =
      jsonDecode(sourceFile.readAsStringSync()) as Map<String, dynamic>;
  final entries = <String, String>{};
  for (final e in sourceArb.entries) {
    if (e.key.startsWith('@')) continue;
    if (e.value is String) entries[e.key] = e.value as String;
  }
  if (entries.isEmpty) {
    stderr.writeln('No translatable keys in $inputPath');
    exit(1);
  }
  stdout.writeln('Found ${entries.length} keys in source ARB.');

  if (service == null || service.isEmpty) {
    stdout.writeln('No --service: nothing to translate.');
    return;
  }
  if ((service == 'deepl' || service == 'google') &&
      (apiKey == null || apiKey.isEmpty)) {
    stderr.writeln('Error: --api-key is required for --service=$service');
    exit(1);
  }

  final translator = _createCliTranslator(
    service,
    apiKey: apiKey,
    email: parsed['email'],
    baseUrl: parsed['base-url'],
  );
  final outDir = Directory(outputPath);
  if (!outDir.existsSync()) outDir.createSync(recursive: true);

  for (final locale in targetLangs) {
    if (locale == sourceLang) continue;
    stdout.writeln('Translating to $locale...');
    final targetPath = '$outputPath/app_$locale.arb';
    final existing = _loadOrCreateArb(targetPath);
    final toTranslate = <String, String>{};
    for (final e in entries.entries) {
      if (force || !existing.containsKey(e.key)) toTranslate[e.key] = e.value;
    }
    if (toTranslate.isEmpty) {
      stdout.writeln('  All keys present. Use --force to redo.');
      continue;
    }
    try {
      final protected = <String, (String, List<String>)>{};
      for (final e in toTranslate.entries) {
        protected[e.key] = _cliPlaceholderProtect(e.value);
      }
      final results = await translator(
        protected.values.map((x) => x.$1).toList(),
        targetLang: locale,
        sourceLang: sourceLang,
      );
      existing['@@locale'] = locale;
      for (final key in toTranslate.keys) {
        final (protectedText, placeholders) = protected[key]!;
        final translated = results[protectedText] ?? toTranslate[key]!;
        existing[key] = _cliPlaceholderRestore(translated, placeholders);
      }
      _writeArb(targetPath, existing);
      stdout.writeln('  Wrote $targetPath');
    } catch (e) {
      stderr.writeln('  Error: $e');
    }
  }
}

// --- Placeholder guard (no Flutter) ---
final _phPatterns = [
  RegExp(r'\{\{(\w+)\}\}'),
  RegExp(r'\{(\w+)\}'),
  RegExp(r'\$(\w+)'),
];

(String, List<String>) _cliPlaceholderProtect(String text) {
  final placeholders = <String>[];
  var result = text;
  for (final re in _phPatterns) {
    result = result.replaceAllMapped(re, (m) {
      placeholders.add(m.group(0)!);
      return '<x id="ph_${placeholders.length - 1}"/>';
    });
  }
  return (result, placeholders);
}

String _cliPlaceholderRestore(String text, List<String> placeholders) {
  var result = text;
  for (var i = 0; i < placeholders.length; i++) {
    result = result.replaceAll('<x id="ph_$i"/>', placeholders[i]);
  }
  return result;
}

/// Extracts translatable string literals from Dart AST.
///
/// This captures:
/// - Text/SelectableText positional strings
/// - TextSpan/RichText literals
/// - Common UI named args (title/description/label/message/content/etc)
///   so strings stored in UI data models are included too.
Set<String> _scanDartStrings(Directory dir) {
  final out = <String>{};
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final content = entity.readAsStringSync();
    final parsed = parseString(
      content: content,
      path: entity.path,
      throwIfDiagnostics: false,
    );
    parsed.unit.visitChildren(_StringCollector(out));
  }
  return out;
}

class _StringCollector extends RecursiveAstVisitor<void> {
  _StringCollector(this.out);

  final Set<String> out;

  static const Set<String> _namedArgs = {
    'text',
    'title',
    'description',
    'label',
    'message',
    'content',
    'subtitle',
    'hintText',
    'helperText',
    'buttonText',
    'tooltip',
    'semanticLabel',
    'semanticsLabel',
  };

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final className = node.constructorName.type.toSource().split('.').last;
    final ctor = node.constructorName.name?.name;
    final args = node.argumentList;

    // Text('...'), SelectableText('...')
    if ((className == 'Text' || className == 'SelectableText') &&
        ctor != 'rich') {
      _collectFirstPositional(args);
    }

    // TextSpan(text: '...') also supports positional first argument.
    if (className == 'TextSpan') {
      _collectFirstPositional(args);
    }

    _collectNamedArgs(args);

    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final callee = node.methodName.name;
    final target = node.target;
    final targetName = target is SimpleIdentifier ? target.name : null;

    // Text('...'), SelectableText('...')
    if ((callee == 'Text' || callee == 'SelectableText') && target == null) {
      _collectFirstPositional(node.argumentList);
    }
    // Text.rich(...)
    if (targetName == 'Text' && callee == 'rich') {
      _collectNamedArgs(node.argumentList);
    }
    // TextSpan(...)
    if (callee == 'TextSpan' && target == null) {
      _collectFirstPositional(node.argumentList);
    }
    // Local helper methods often build UI text from literal args
    // (e.g. _buildTitleLine('prefix', 'highlight', '.')).
    if (target == null) {
      final positional = node.argumentList.arguments
          .where((a) => a is! NamedExpression)
          .cast<Expression>()
          .toList();
      for (final arg in positional) {
        if (_canExtractString(arg)) {
          _collectFromExpression(arg);
        }
      }
    }

    _collectNamedArgs(node.argumentList);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier &&
        (function.name == 'Text' || function.name == 'SelectableText')) {
      _collectFirstPositional(node.argumentList);
      _collectNamedArgs(node.argumentList);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  void _collectNamedArgs(ArgumentList args) {
    for (final arg in args.arguments) {
      if (arg is! NamedExpression) continue;
      final name = arg.name.label.name;
      if (_namedArgs.contains(name)) {
        _collectFromExpression(arg.expression);
      }
    }
  }

  void _collectFirstPositional(ArgumentList args) {
    for (final arg in args.arguments) {
      if (arg is NamedExpression) continue;
      _collectFromExpression(arg);
      return;
    }
  }

  void _collectFromExpression(Expression expression) {
    if (expression is ParenthesizedExpression) {
      _collectFromExpression(expression.expression);
      return;
    }
    if (expression is ConditionalExpression) {
      _collectFromExpression(expression.thenExpression);
      _collectFromExpression(expression.elseExpression);
      return;
    }
    if (expression is BinaryExpression && expression.operator.lexeme == '+') {
      _collectFromExpression(expression.leftOperand);
      _collectFromExpression(expression.rightOperand);
      return;
    }

    final text = _stringFromExpression(expression);
    if (text == null) return;
    final normalized = text.trim();
    if (normalized.isNotEmpty) {
      out.add(normalized);
    }
  }

  bool _canExtractString(Expression expression) {
    if (expression is ParenthesizedExpression) {
      return _canExtractString(expression.expression);
    }
    if (_stringFromExpression(expression) != null) return true;
    if (expression is ConditionalExpression) {
      // Mixed branches are common for UI fallbacks:
      // (msg != null) ? msg : 'Fallback text'
      // We still want to extract the literal branch.
      return _canExtractString(expression.thenExpression) ||
          _canExtractString(expression.elseExpression);
    }
    if (expression is BinaryExpression && expression.operator.lexeme == '+') {
      return _canExtractString(expression.leftOperand) ||
          _canExtractString(expression.rightOperand);
    }
    return false;
  }

  String? _stringFromExpression(Expression expression) {
    if (expression is SimpleStringLiteral) {
      return expression.value;
    }
    if (expression is StringInterpolation) {
      final buffer = StringBuffer();
      for (final element in expression.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else if (element is InterpolationExpression) {
          final expr = element.expression;
          if (expr is SimpleIdentifier) {
            buffer.write('\$${expr.name}');
          } else {
            buffer.write('\${${expr.toSource()}}');
          }
        }
      }
      return buffer.toString();
    }
    if (expression is AdjacentStrings) {
      final buffer = StringBuffer();
      for (final s in expression.strings) {
        final part = _stringFromExpression(s);
        if (part == null) return null;
        buffer.write(part);
      }
      return buffer.toString();
    }
    return null;
  }
}

Map<String, dynamic> _loadOrCreateArb(String path) {
  final f = File(path);
  if (f.existsSync()) {
    return Map<String, dynamic>.from(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
  }
  return <String, dynamic>{};
}

void _writeArb(String path, Map<String, dynamic> arb) {
  const encoder = JsonEncoder.withIndent('  ');
  File(path).writeAsStringSync('${encoder.convert(arb)}\n');
}

typedef CliTranslateBatch = Future<Map<String, String>> Function(
  List<String> texts, {
  required String targetLang,
  String sourceLang,
});

CliTranslateBatch _createCliTranslator(
  String service, {
  String? apiKey,
  String? email,
  String? baseUrl,
}) {
  switch (service.toLowerCase()) {
    case 'google':
      if (apiKey == null || apiKey.isEmpty)
        throw ArgumentError('apiKey required for google');
      return (texts, {required targetLang, sourceLang = 'en'}) => _cliGoogle(
          texts,
          targetLang: targetLang,
          sourceLang: sourceLang,
          apiKey: apiKey);
    case 'mymemory':
      return (texts, {required targetLang, sourceLang = 'en'}) => _cliMyMemory(
          texts,
          targetLang: targetLang,
          sourceLang: sourceLang,
          email: email);
    case 'lingva':
      return (texts, {required targetLang, sourceLang = 'en'}) => _cliLingva(
          texts,
          targetLang: targetLang,
          sourceLang: sourceLang,
          baseUrl: baseUrl ?? 'https://lingva.ml');
    case 'mock':
      return (texts, {required targetLang, sourceLang = 'en'}) =>
          _cliMock(texts, targetLang: targetLang);
    case 'deepl':
      if (apiKey == null || apiKey.isEmpty)
        throw ArgumentError('apiKey required for deepl');
      return (texts, {required targetLang, sourceLang = 'en'}) => _cliDeepL(
          texts,
          targetLang: targetLang,
          sourceLang: sourceLang,
          apiKey: apiKey);
    default:
      throw ArgumentError('Unknown service: $service');
  }
}

Future<Map<String, String>> _cliDeepL(
  List<String> texts, {
  required String targetLang,
  String sourceLang = 'en',
  required String apiKey,
}) async {
  final results = <String, String>{};
  final protected = <String, (String, List<String>)>{};
  for (final text in texts) {
    final (protectedText, placeholders) = _cliPlaceholderProtect(text);
    protected[text] = (_cliEscapeXmlExceptPlaceholders(protectedText), placeholders);
  }
  final baseUrl = apiKey.endsWith(':fx')
      ? 'https://api-free.deepl.com/v2'
      : 'https://api.deepl.com/v2';
  try {
    final response = await http.post(
      Uri.parse('$baseUrl/translate'),
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
          final restored = _cliPlaceholderRestore(translatedText, placeholders);
          results[original] = _cliDecodeXmlEntities(restored);
        } else {
          results[original] = original;
        }
        i++;
      }
    } else {
      print('[auto_l10n] DeepL error ${response.statusCode}: ${response.body}');
      for (final text in texts) results[text] = text;
    }
  } catch (e) {
    print('[auto_l10n] DeepL request failed: $e');
    for (final text in texts) results[text] = text;
  }
  return results;
}

final RegExp _cliPlaceholderTag = RegExp(r'<x id="ph_\d+"/>');

String _cliEscapeXmlExceptPlaceholders(String input) {
  final out = StringBuffer();
  var index = 0;
  for (final m in _cliPlaceholderTag.allMatches(input)) {
    if (m.start > index) {
      out.write(_cliEscapeXml(input.substring(index, m.start)));
    }
    out.write(m.group(0)!);
    index = m.end;
  }
  if (index < input.length) {
    out.write(_cliEscapeXml(input.substring(index)));
  }
  return out.toString();
}

String _cliEscapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _cliDecodeXmlEntities(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

Future<Map<String, String>> _cliGoogle(
  List<String> texts, {
  required String targetLang,
  String sourceLang = 'en',
  required String apiKey,
}) async {
  const baseUrl = 'https://translation.googleapis.com/language/translate/v2';
  final results = <String, String>{};
  final protected = <String, (String, List<String>)>{};
  for (final text in texts) protected[text] = _cliPlaceholderProtect(text);
  try {
    final response = await http.post(
      Uri.parse('$baseUrl?key=$apiKey'),
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
          final translatedText = translations[i]['translatedText'] as String;
          final (_, placeholders) = protected[original]!;
          results[original] =
              _cliPlaceholderRestore(translatedText, placeholders);
        } else {
          results[original] = original;
        }
        i++;
      }
    } else {
      print(
          '[auto_l10n] Google error ${response.statusCode}: ${response.body}');
      for (final text in texts) results[text] = text;
    }
  } catch (e) {
    print('[auto_l10n] Google request failed: $e');
    for (final text in texts) results[text] = text;
  }
  return results;
}

Future<Map<String, String>> _cliMyMemory(
  List<String> texts, {
  required String targetLang,
  String sourceLang = 'en',
  String? email,
}) async {
  final results = <String, String>{};
  final langMap = {'zh': 'zh-CN'};
  String lang(String l) => langMap[l] ?? l;
  for (final text in texts) {
    try {
      final (protectedText, placeholders) = _cliPlaceholderProtect(text);
      final params = {
        'q': protectedText,
        'langpair': '${lang(sourceLang)}|${lang(targetLang)}'
      };
      if (email != null) params['de'] = email;
      final uri = Uri.https('api.mymemory.translated.net', '/get', params);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['responseData'] as Map<String, dynamic>;
        final translated = data['translatedText'] as String;
        results[text] = _cliPlaceholderRestore(translated, placeholders);
      } else {
        results[text] = text;
      }
    } catch (e) {
      results[text] = text;
    }
  }
  return results;
}

Future<Map<String, String>> _cliLingva(
  List<String> texts, {
  required String targetLang,
  String sourceLang = 'en',
  String baseUrl = 'https://lingva.ml',
}) async {
  final results = <String, String>{};
  for (final text in texts) {
    try {
      final (protectedText, placeholders) = _cliPlaceholderProtect(text);
      final encoded = Uri.encodeComponent(protectedText);
      final url = '$baseUrl/api/v1/$sourceLang/$targetLang/$encoded';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final translated = json['translation'] as String;
        results[text] = _cliPlaceholderRestore(translated, placeholders);
      } else {
        results[text] = text;
      }
    } catch (e) {
      results[text] = text;
    }
  }
  return results;
}

Future<Map<String, String>> _cliMock(
  List<String> texts, {
  required String targetLang,
}) async {
  await Future.delayed(const Duration(milliseconds: 100));
  return {for (final t in texts) t: '[$targetLang] $t'};
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
        result[stripped.substring(0, eqIndex)] =
            stripped.substring(eqIndex + 1);
      }
    }
  }
  return result;
}
