import 'package:flutter/material.dart';

import 'src/binding.dart';
import 'src/translation_provider.dart';
import 'src/translator.dart';

/// One-line entry point for auto_l10n. Forwards all parameters to [AutoL10nBinding.ensureInitialized].
AutoL10nBinding autoL10n({
  AbstractTranslator? translator,
  TranslationProvider? provider,
  String? apiKey,
  String? email,
  String? baseUrl,
  String? translationsPath,
  bool loadPregenerated = true,
  AutoL10nLayoutPolicy layoutPolicy = AutoL10nLayoutPolicy.safeEllipsisCurrent,
  Locale? targetLocale,
  Locale sourceLocale = const Locale('en'),
}) =>
    AutoL10nBinding.ensureInitialized(
      translator: translator,
      provider: provider,
      apiKey: apiKey,
      email: email,
      baseUrl: baseUrl,
      translationsPath: translationsPath,
      loadPregenerated: loadPregenerated,
      layoutPolicy: layoutPolicy,
      targetLocale: targetLocale,
      sourceLocale: sourceLocale,
    );
