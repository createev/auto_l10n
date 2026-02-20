# auto_l10n example

This app shows:

- **Pre-generated ARB** — static strings from `assets/auto_l10n` (from the generate CLI)
- **Locale picker** — switch language at runtime (EN, ES, DE, FR, RU, JA, ZH); uses `AutoL10nBinding.setLocale()`
- **User-generated content** — type in the field and tap Submit; the submitted text is translated and shown below

## Run with DeepL (recommended)

1. Copy `lib/env.example.dart` to `lib/env.dart`.
2. Put your [DeepL API key](https://www.deepl.com/pro-api) in `kDeeplApiKey` in `lib/env.dart`.
3. Add `lib/env.dart` to `.gitignore` so the key is not committed.
4. Run:

   ```bash
   flutter run
   ```

Strings load from ARB first; any new or dynamic text is sent to DeepL and cached. After the first run, translations load from cache so the app feels instant.

## Run without an API key

To try the example without a key:

- Use **pre-generated only**: in `main.dart` call `autoL10n()` with no `provider`/`apiKey` — the app will only use ARB files (no runtime API). Change the initial `_selected` in `HomePage` if needed to match a locale you have ARB for.
- Or use **MyMemory** (free, no key): `autoL10n(provider: TranslationProvider.mymemory, targetLocale: const Locale('es'));`
- Or use **Mock** (for demos): `autoL10n(provider: TranslationProvider.mock, targetLocale: const Locale('es'));` — strings get a `[locale]` prefix.

## Other providers

In `main.dart`, you can switch to another built-in provider, for example:

```dart
autoL10n(
  provider: TranslationProvider.google,
  apiKey: 'YOUR_GOOGLE_CLOUD_TRANSLATION_KEY',
  targetLocale: const Locale('es'),
);
```

Or pass a custom `translator: MyTranslator()` that implements `AbstractTranslator`.
