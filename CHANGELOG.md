## 0.1.0

- Initial release.
- Runtime translation for Flutter `Text` and `RichText` via `AutoL10nBinding`.
- Built-in providers: DeepL, MyMemory, Lingva, Google Translate, Mock.
- Optional `targetLocale` (defaults to device locale).
- Custom translators via `AbstractTranslator`.
- Per-language cache in memory and SharedPreferences.
- Static ARB generation: `dart run auto_l10n:generate`.
