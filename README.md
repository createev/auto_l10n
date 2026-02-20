# auto_l10n

*The name uses the numeronym **l10n** — *l* + 10 letters + *n* = **localization**.*

Automatic Flutter app translation with zero code changes. Add one line to `main.dart` and all `Text` and `RichText` widgets are translated at runtime. Optionally generate and load ARB files so static strings come from assets and only new/dynamic text uses the API.

## Quickstart

**1. Add the dependency**

```yaml
# pubspec.yaml
dependencies:
  auto_l10n: ^0.2.0
```

**2. (Optional)** Generate ARB from code → fills `assets/auto_l10n` for instant static translations; the rest can be translated at runtime with the API variant.

```bash
flutter pub get
dart run auto_l10n --service=deepl --api-key=YOUR_DEEPL_KEY
```

**3. One line in `main.dart`**

Pre-generated only (no API key, loads from `assets/auto_l10n`):

```dart
import 'package:auto_l10n/auto_l10n.dart';

void main() {
  autoL10n();
  runApp(const MyApp());
}
```

Or with DeepL so that strings not in the generated ARB are translated on the fly:

```dart
import 'package:auto_l10n/auto_l10n.dart';

void main() {
  autoL10n(
    provider: TranslationProvider.DeepL,
    apiKey: 'YOUR_DEEPL_KEY',
  );
  runApp(const MyApp());
}
```

## How It Works

1. `autoL10n()` hooks into Flutter's rendering pipeline (via a custom binding)
2. After each frame, it scans the widget tree for `Text` and `RichText` widgets
3. When `loadPregenerated` is true (default), ARB from `translationsPath` (default `assets/auto_l10n`) is loaded first; any string not in that set is sent to the translation API when `provider`/`translator` is set. Set `loadPregenerated: false` for API-only mode.
4. New strings are collected for 300ms (debounced) then sent in one batch
5. Translated strings are written directly to `RenderParagraph` objects
6. All translations are cached in `SharedPreferences` — second launch is instant

## autoL10n options

| Scenario | Code |
|--------|-----|
| **API only** (no pre-generated ARB) | `autoL10n(provider: ..., apiKey: ..., loadPregenerated: false)` |
| **Pre-generated ARB + API for new strings** | `autoL10n(provider: ..., apiKey: ...)` — loads from default `assets/auto_l10n`, translates the rest via API |
| **Pre-generated ARB only** (no API) | `autoL10n()` — loads from default `assets/auto_l10n` only |

`translationsPath` is optional; when omitted, `assets/auto_l10n` is used by default (same as the generate CLI output). Set **`loadPregenerated: false`** to disable loading from ARB and use only the translation API. **If you use pre-generated ARB:** add `assets/auto_l10n` to `flutter: assets:` in `pubspec.yaml` unless you already have `assets: - assets/`.

## Built-in providers

Use [TranslationProvider] and optional [apiKey]:

| Provider | API key | Notes |
|----------|---------|--------|
| `TranslationProvider.DeepL` | **yes** | Free/pro auto-detected by key |
| `TranslationProvider.mymemory` | no | Free, 5k words/day; optional `email` for 50k |
| `TranslationProvider.lingva` | no | Free, public Lingva instances |
| `TranslationProvider.google` | **yes** | Google Cloud Translation v2 |
| `TranslationProvider.mock` | no | Prefixes with `[langCode]` for demos/tests |

**All parameters** (example with DeepL; omit what you don’t need):

```dart
autoL10n(
  provider: TranslationProvider.DeepL,   // or mymemory, lingva, google, mock — or translator: MyTranslator()
  translator: null,                      // optional: your own AbstractTranslator
  apiKey: 'YOUR_DEEPL_KEY',             // required for DeepL / Google
  translationsPath: 'assets/auto_l10n',  // default; pre-generated ARB
  loadPregenerated: true,                // false = API only
  targetLocale: const Locale('es'),      // default: device locale
  sourceLocale: const Locale('en'),      // default: en
  email: null,                           // e.g. MyMemory
  baseUrl: null,                         // custom endpoint
);
```

Use `translator: MyTranslator()` (implementing [AbstractTranslator]) to plug in your own translation API instead of a built-in provider. See [createTranslator] and [autoL10n].

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

## Generate CLI

Generate ARB files from code or from an existing ARB, then optionally translate into other locales. Output is written to `assets/auto_l10n` by default; the app loads these files from the asset bundle at runtime (no Dart codegen). If your `pubspec.yaml` already includes `assets: - assets/`, no extra asset entry is needed.

**From code (default):** scan Dart files, merge strings into a source ARB, optionally translate to target locales.

```bash
# No --service: scan only (merge strings from lib/ into assets/auto_l10n). No API call.
dart run auto_l10n

# With --service (and --api-key): scan + translate to default target languages (DeepL example)
dart run auto_l10n --service=deepl --api-key=YOUR_DEEPL_KEY

# Custom target languages
dart run auto_l10n --service=deepl --api-key=YOUR_DEEPL_KEY --target-langs=ru,de,es
```

**From ARB:** use an existing ARB as source and translate into other locale files.

```bash
dart run auto_l10n --from=arb --input-path=l10n/app_en.arb --target-langs=ru,de --service=deepl --api-key=YOUR_DEEPL_KEY
```

### Generate: full parameter table

| Parameter | Mode | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| **Mode & paths** |
| `--from=code` | — | no | `code` | Scan code → ARB. |
| `--from=arb` | — | no | — | Source ARB → translate into other ARB files. |
| `--input-path=path` | both | no | see below | Where to read from. |
| `--output-path=path` | both | no | `assets/auto_l10n` | Where to write ARB (and where the app loads from by default). |
| **Languages** |
| `--source-lang=code` | both | no | `en` | Source language. |
| `--target-langs=ru,de,...` | both | no | see below | Target languages for translation. |
| **Behavior** |
| `--force` | both | no | — | Overwrite existing keys/translations. |
| **API** |
| `--api-key=key` | both | when translating | — | API key (DeepL, Google, etc.). |
| `--service=name` | both | when translating | — | Omit to skip translation. When set: `deepl` \| `google` \| `mymemory` \| `lingva` |
| `--email=email` | both | no | — | For services like MyMemory. |
| `--base-url=url` | both | no | — | Custom API endpoint. |

**`--input-path` default:** from-code → `lib/` (code directory). from-arb → `l10n/app_<source-lang>.arb`.

**`--target-langs`:** when omitted and `--service` is set → translate to default set **es, de, fr, pt, ru, zh, ja** (both from-code and from-arb). No `--service` → no translation. When set → only those locales.

**Assets:** If `assets/auto_l10n` isn’t already covered (e.g. by `assets: - assets/`), add it under `flutter: assets:` in `pubspec.yaml`.

## Performance & Caching

- First launch: strings appear in English, then update after ~300-500ms
- Second launch: translations load from `SharedPreferences` instantly, no API calls
- To clear cache (e.g. for debugging): `await AutoL10nBinding.clearCache();` from your app or before `autoL10n()` in `main() async { ... }`
- Strings that are only digits, punctuation, or likely enum values are skipped
- All strings on a screen are batched into a single API request
- Placeholders (`{name}`, `$variable`) are protected from translation APIs

## Limitations

- Translates only `Text` and `RichText` widgets (including nested [TextSpan]s in RichText). Strings in custom painters, platform views, or non-widget contexts are not translated.
- First screen on first launch shows original strings for ~300-500ms while translation loads. Subsequent launches are instant.
- Translation quality depends on the chosen API. Strings without surrounding context may be less accurate than human-translated content.
- Does not handle ICU plural syntax. Plurals require manual ARB authoring (e.g. with flutter gen-l10n).
- Not a replacement for proper localization in production apps. Best suited for prototypes, indie apps, and quick market testing.
