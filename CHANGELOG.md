## Unreleased

- Runtime bootstrap is now deterministic: `SharedPreferences cache -> ARB preload -> API fallback`.
- ARB-only mode no longer uses `NoOpTranslator` in runtime pipeline; API queue/flush is skipped when no translator is configured.
- Unified cache key namespace by language: `auto_l10n_<lang>` (instead of translator-scoped keys).
- Runtime cache no longer stores unchanged entries (`translated == original`).
- Runtime translation patching now also handles `Text.textSpan` (in addition to `Text.data` and `RichText`).
- Runtime fallback improved for whitespace-mismatch keys (trimmed lookup with preserved outer whitespace).
- Retry behavior for failed API batches: up to 3 retry attempts, then stop until new input arrives.
- DeepL XML mode fixes: safe XML escaping around placeholders and entity decode after translation.
- CLI extraction upgraded to AST-first scanning and expanded to capture real-world UI patterns.
- CLI now captures fallback literals in mixed expressions (e.g. ternary with one non-literal branch).
- CLI now captures string arguments from mixed-signature calls (e.g. string + enum arguments in one call).
- CLI keys are normalized with trim by default (cleaner ARB keys).

## 0.2.0

- **Generate CLI** (`dart run auto_l10n`): from-code (scan `Text('...')` / `Text("...")`) or from-arb; optional `--service` (deepl, google, mymemory, lingva, mock) with `--api-key` for deepl/google. Output to `assets/auto_l10n` by default.
- **Pre-generated ARB only**: `autoL10n()` with no provider loads from `translationsPath` (default `assets/auto_l10n`); no API key required.
- **Pre-generated + API**: `autoL10n(provider: ..., apiKey: ...)` loads ARB first, translates missing strings via API.
- **API only**: `autoL10n(provider: ..., loadPregenerated: false)`.
- **`autoL10n()`** top-level helper; `translationsPath` and `loadPregenerated` parameters on binding.
- **TranslationCache**: optional preloaded map; `addPreloaded()` for async ARB load and persist.
- **NoOpTranslator** when only pre-generated ARB is used.
- **RichText** widgets are now patched and restored: translated text is shown in `RichText` / nested `TextSpan`s, not only in `Text`.
- Example app: user-generated content (text field → translated output), locale picker (device locale on launch with fallback to en), in-app copy about API key vs free providers, pre-generated ARB.

## 0.1.0

- Initial release.
- Runtime translation for Flutter `Text` and `RichText` via `AutoL10nBinding`.
- Built-in providers: DeepL, MyMemory, Lingva, Google Translate, Mock.
- Optional `targetLocale` (defaults to device locale).
- Custom translators via `AbstractTranslator`.
- Per-language cache in memory and SharedPreferences.
- Static ARB generation: `dart run auto_l10n:generate`.
