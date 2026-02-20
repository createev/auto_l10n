import 'package:auto_l10n/auto_l10n.dart';
import 'package:flutter/material.dart';

import 'env.dart';

void main() {
  autoL10n();
  // autoL10n(
  //   provider: TranslationProvider.DeepL,
  //   apiKey: kDeeplApiKey,
  //   targetLocale: const Locale('es'),
  // );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Locale code -> flag emoji (one row of buttons).
  static const _localeFlags = {
    'en': '🇬🇧',
    'es': '🇪🇸',
    'de': '🇩🇪',
    'fr': '🇫🇷',
    'ru': '🇷🇺',
    'ja': '🇯🇵',
    'zh': '🇨🇳',
  };

  String _selected = 'es'; // must match targetLocale in main()
  final TextEditingController _userInputController = TextEditingController();

  /// Text submitted for translation (UGC: translated on Submit).
  String _submittedText = '';

  @override
  void dispose() {
    _userInputController.dispose();
    super.dispose();
  }

  void _onSubmitUgc() {
    setState(() => _submittedText = _userInputController.text.trim());
  }

  void _onLocaleChanged(String code) {
    setState(() => _selected = code);
    AutoL10nBinding.setLocale(Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hello World')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Locale picker: one row of flag buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in _localeFlags.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Material(
                        borderRadius: BorderRadius.circular(8),
                        color:
                            e.key == _selected
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _onLocaleChanged(e.key),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              e.value,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Current locale: $_selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),

              // Translatable content
              const Text('Welcome to auto_l10n'),
              const SizedBox(height: 12),
              const Text('This text is translated automatically'),
              const SizedBox(height: 12),
              const Text(
                'Use your API key (DeepL for best quality) or free providers with no key.',
              ),
              const SizedBox(height: 12),
              const Text('Add one line to main.dart and you are done'),
              const SizedBox(height: 16),
              Text(
                'Example: add to main.dart',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText.rich(
                  _buildHighlightedCode(context, _exampleCode),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text(
                'User-generated content',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Type below and press Submit — the text will be translated to the selected locale.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _userInputController,
                  decoration: const InputDecoration(
                    hintText: 'Type something...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _onSubmitUgc,
                child: const Text('Submit'),
              ),
              if (_submittedText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Translated:',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(_submittedText),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static const String _exampleCode = r'''
void main() {
  autoL10n(
    provider: TranslationProvider.DeepL,
    apiKey: 'YOUR_DEEPL_KEY',
    targetLocale: const Locale('es'),
  );
  runApp(const MyApp());
}
''';

  static const _keywords = {
    'void',
    'main',
    'const',
    'runApp',
    'return',
    'class',
    'extends',
    'provider',
    'translator',
  };

  TextSpan _buildHighlightedCode(BuildContext context, String code) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall!.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['monospace'],
      fontSize: 12,
      color: theme.colorScheme.onSurface,
    );
    final keywordColor =
        theme.brightness == Brightness.dark
            ? const Color(0xFF81A2BE)
            : const Color(0xFF0550AE);
    final stringColor =
        theme.brightness == Brightness.dark
            ? const Color(0xFFB5BD68)
            : const Color(0xFF0D6938);
    final typeColor =
        theme.brightness == Brightness.dark
            ? const Color(0xFF8ABEB7)
            : const Color(0xFF953800);
    final punctuationColor = theme.colorScheme.onSurface.withValues(alpha: 0.8);

    final spans = <TextSpan>[];
    var i = 0;
    while (i < code.length) {
      if (code[i] == "'" || code[i] == '"') {
        final quote = code[i];
        final start = i;
        i++;
        while (i < code.length && code[i] != quote) {
          if (code[i] == '\\') i++;
          i++;
        }
        if (i < code.length) i++;
        spans.add(
          TextSpan(
            text: code.substring(start, i),
            style: baseStyle.copyWith(color: stringColor),
          ),
        );
        continue;
      }
      if (_isLetterOrUnderscore(code[i])) {
        final start = i;
        while (i < code.length && _isWordChar(code[i])) {
          i++;
        }
        final word = code.substring(start, i);
        if (_keywords.contains(word)) {
          spans.add(
            TextSpan(
              text: word,
              style: baseStyle.copyWith(color: keywordColor),
            ),
          );
        } else if (word.startsWith(RegExp(r'[A-Z]'))) {
          spans.add(
            TextSpan(text: word, style: baseStyle.copyWith(color: typeColor)),
          );
        } else {
          spans.add(TextSpan(text: word, style: baseStyle));
        }
        continue;
      }
      if (code[i] == '(' ||
          code[i] == ')' ||
          code[i] == '{' ||
          code[i] == '}' ||
          code[i] == ',' ||
          code[i] == ';' ||
          code[i] == '.') {
        spans.add(
          TextSpan(
            text: code[i],
            style: baseStyle.copyWith(color: punctuationColor),
          ),
        );
        i++;
        continue;
      }
      final start = i;
      while (i < code.length &&
          code[i] != "'" &&
          code[i] != '"' &&
          !_isLetterOrUnderscore(code[i]) &&
          code[i] != '(' &&
          code[i] != ')' &&
          code[i] != '{' &&
          code[i] != '}' &&
          code[i] != ',' &&
          code[i] != ';' &&
          code[i] != '.') {
        i++;
      }
      if (start < i) {
        spans.add(TextSpan(text: code.substring(start, i), style: baseStyle));
      }
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  static bool _isLetterOrUnderscore(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
  }

  static bool _isWordChar(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return _isLetterOrUnderscore(c) || (u >= 48 && u <= 57);
  }
}
