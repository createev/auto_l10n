# auto_l10n

Automatic Flutter app translation with zero code changes. Add one line to `main.dart` and all `Text` widgets are translated at runtime.

## Quickstart

```yaml
# pubspec.yaml
dependencies:
  auto_l10n: ^0.1.0
```

```dart
// main.dart
import 'package:auto_l10n/auto_l10n.dart';

void main() {
  AutoL10nBinding.ensureInitialized(
    provider: TranslationProvider.DeepL,
    apiKey: 'YOUR_DEEPL_KEY',
    targetLocale: const Locale('es'),  // optional: defaults to device locale
  );
  runApp(const MyApp());
}
```

No other files need to change. To use your own translation backend, pass `translator: MyTranslator()` instead of `provider`.

## How It Works

1. `AutoL10nBinding` hooks into Flutter's rendering pipeline
2. After each frame, it scans the widget tree for `Text` and `RichText` widgets
3. New strings are collected for 300ms (debounced) then sent to the translation API in one batch
4. Translated strings are written directly to `RenderParagraph` objects
5. All translations are cached in `SharedPreferences` — second launch is instant

## Built-in providers

Use [TranslationProvider] and optional [apiKey]:

| Provider | API key | Notes |
|----------|---------|--------|
| `TranslationProvider.DeepL` | **yes** | Free/pro auto-detected by key |
| `TranslationProvider.mymemory` | no | Free, 5k words/day; optional `email` for 50k |
| `TranslationProvider.lingva` | no | Free, public Lingva instances |
| `TranslationProvider.google` | **yes** | Google Cloud Translation v2 |
| `TranslationProvider.mock` | no | Prefixes with `[langCode]` for demos/tests |

```dart
// DeepL (recommended)
AutoL10nBinding.ensureInitialized(
  provider: TranslationProvider.DeepL,
  apiKey: 'YOUR_KEY',
  targetLocale: const Locale('es'),  // omit to use device locale
);

// Free, no key
AutoL10nBinding.ensureInitialized(
  provider: TranslationProvider.mymemory,
  targetLocale: const Locale('es'),
);
```

Options: `email`, `baseUrl`. See [createTranslator] and [AutoL10nBinding.ensureInitialized].

## Custom translator

Pass [translator] instead of [provider]. Implement [AbstractTranslator]:

```dart
class MyTranslator implements AbstractTranslator {
  @override
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    required String targetLang,
    String sourceLang = 'en',
  }) async {
    // Call your API, return Map<original, translated>
  }
}
```

## Mode 2: Static ARB Generation

If your app already uses `AppLocalizations`, you can auto-translate ARB files:

```bash
dart run auto_l10n:generate \
  --api-key=YOUR_KEY \
  --source=lib/l10n/app_en.arb \
  --targets=ru,de,fr,ja,es \
  --service=deepl
```

| Flag | Required | Default | Description |
|---|---|---|---|
| `--source` | yes | — | Path to source ARB file |
| `--targets` | yes | — | Comma-separated locale codes |
| `--api-key` | yes | — | API key for chosen service |
| `--service` | no | `deepl` | `deepl` or `google` |
| `--force` | no | false | Re-translate existing keys |

Output is compatible with `flutter gen-l10n`.

## Performance & Caching

- First launch: strings appear in English, then update after ~300-500ms
- Second launch: translations load from `SharedPreferences` instantly, no API calls
- Strings that are only digits, punctuation, or likely enum values are skipped
- All strings on a screen are batched into a single API request
- Placeholders (`{name}`, `$variable`) are protected from translation APIs

## Limitations

- Translates only `Text` and `RichText` widgets. Strings in custom painters, platform views, or non-widget contexts are not translated.
- First screen on first launch shows original strings for ~300-500ms while translation loads. Subsequent launches are instant.
- Translation quality depends on the chosen API. Strings without surrounding context may be less accurate than human-translated content.
- Does not handle ICU plural syntax. Plurals require Mode 2 with manual ARB authoring.
- Not a replacement for proper localization in production apps. Best suited for prototypes, indie apps, and quick market testing.
