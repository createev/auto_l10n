/// Automatic Flutter app translation with zero code changes.
///
/// Add one line to `main.dart` and all `Text` widgets are translated
/// at runtime. Supports DeepL, Google Translate, and custom translators.
library auto_l10n;

export 'auto_l10n_init.dart' show autoL10n;
export 'src/binding.dart';
export 'src/placeholder_guard.dart';
export 'src/translation_cache.dart';
export 'src/translation_provider.dart';
export 'src/translator.dart';
export 'src/tree_scanner.dart';
export 'src/translators/deepl_translator.dart';
export 'src/translators/google_translator.dart';
export 'src/translators/lingva_translator.dart';
export 'src/translators/mock_translator.dart';
export 'src/translators/mymemory_translator.dart';
export 'src/translators/noop_translator.dart';
