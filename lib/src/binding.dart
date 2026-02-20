import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'translation_cache.dart';
import 'translation_provider.dart';
import 'translator.dart';
import 'tree_scanner.dart';

/// Custom binding that hooks into the Flutter rendering pipeline
/// to automatically translate [Text] widgets.
///
/// Must be initialized before [runApp].
///
/// **Simple (built-in provider):**
/// ```dart
/// AutoL10nBinding.ensureInitialized(
///   provider: TranslationProvider.mymemory,
///   targetLocale: const Locale('es'),  // optional: defaults to device locale
/// );
/// ```
///
/// **With API key (DeepL / Google):**
/// ```dart
/// AutoL10nBinding.ensureInitialized(
///   provider: TranslationProvider.DeepL,
///   apiKey: 'your-key',
/// );
/// ```
///
/// **Custom translator:**
/// ```dart
/// AutoL10nBinding.ensureInitialized(
///   translator: MyCustomTranslator(),
///   targetLocale: const Locale('ru'),
/// );
/// ```
class AutoL10nBinding extends WidgetsFlutterBinding {
  static final Map<String, TranslationCache> _cachesByLang = {};
  static AbstractTranslator? _translator;
  static String _sourceLang = 'en';
  static String _targetLang = '';
  static bool _frameCallbackRegistered = false;

  /// The active translation cache for the current locale, or `null` if source locale.
  static TranslationCache? get cache => _currentCache;

  static TranslationCache? get _currentCache =>
      _isActive ? _cachesByLang[_targetLang] : null;

  /// Whether translation is active (source != target).
  static bool get _isActive => _sourceLang != _targetLang;

  /// Initializes the binding.
  ///
  /// Use either [translator] (custom or any [AbstractTranslator]) or
  /// [provider] + optional [apiKey] for a built-in backend.
  /// [targetLocale] is optional and defaults to the device locale.
  /// [sourceLocale] defaults to `en`. When target matches source,
  /// translation is a no-op.
  static AutoL10nBinding ensureInitialized({
    AbstractTranslator? translator,
    TranslationProvider? provider,
    String? apiKey,
    String? email,
    String? baseUrl,
    Locale? targetLocale,
    Locale sourceLocale = const Locale('en'),
  }) {
    final AbstractTranslator t;
    if (translator != null) {
      t = translator;
    } else if (provider != null) {
      t = createTranslator(
        provider,
        apiKey: apiKey,
        email: email,
        baseUrl: baseUrl,
      );
    } else {
      throw ArgumentError(
        'Either translator or provider must be set.',
      );
    }

    _translator = t;
    _sourceLang = sourceLocale.languageCode;
    final effectiveTarget =
        targetLocale ?? ui.PlatformDispatcher.instance.locale;
    _targetLang = effectiveTarget.languageCode;

    if (_isActive) {
      final c = TranslationCache(
        translator: t,
        targetLang: _targetLang,
        sourceLang: _sourceLang,
      );
      c.loadFromPrefs();
      c.addListener(_onTranslationsReady);
      _cachesByLang[_targetLang] = c;
    }

    final binding = AutoL10nBinding();
    return binding;
  }

  /// Switches the target locale at runtime.
  ///
  /// When [locale] matches the source locale, translation becomes a no-op
  /// and original strings are shown. Caches for other locales are kept
  /// so switching back is instant.
  static void setLocale(Locale locale) {
    final translator = _translator;
    if (translator == null) return;

    _currentCache?.removeListener(_onTranslationsReady);
    _targetLang = locale.languageCode;

    if (_isActive) {
      final c = _cachesByLang[_targetLang] ??= () {
        final cache = TranslationCache(
          translator: translator,
          targetLang: _targetLang,
          sourceLang: _sourceLang,
        );
        cache.loadFromPrefs();
        return cache;
      }();
      c.addListener(_onTranslationsReady);
    }

    // Force rebuild to show original or translated strings
    WidgetsBinding.instance.scheduleFrame();
  }

  static void _onTranslationsReady() {
    final binding = WidgetsBinding.instance;
    final rootElement = binding.rootElement;
    if (rootElement == null) return;

    _patchTextWidgets(rootElement);
    binding.scheduleFrame();
  }

  @override
  void initInstances() {
    super.initInstances();
    if (!_frameCallbackRegistered) {
      addPersistentFrameCallback((_) => _onFrame());
      _frameCallbackRegistered = true;
    }
  }

  static void _onFrame() {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) return;

    final cache = _currentCache;
    if (cache != null) {
      // Scan tree for new strings to translate
      TreeScanner.scan(rootElement, cache);
      // Patch any already-translated Text widgets
      _patchTextWidgets(rootElement);
    } else {
      // Back to source locale: restore original text in all Text widgets
      _restoreTextWidgets(rootElement);
    }
  }

  /// When translation is off (source locale), restores original text in all [Text] widgets.
  static void _restoreTextWidgets(Element root) {
    root.visitChildElements((element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) {
        _updateRenderParagraph(element, widget, widget.data!);
      }
      _restoreTextWidgets(element);
    });
  }

  /// Walks the element tree and updates RenderParagraph objects
  /// with translated text.
  static void _patchTextWidgets(Element root) {
    final cache = _currentCache;
    if (cache == null) return;

    root.visitChildElements((element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null && cache.has(widget.data!)) {
        final translated = cache.translate(widget.data!);
        if (translated != widget.data) {
          _updateRenderParagraph(element, widget, translated);
        }
      }
      _patchTextWidgets(element);
    });
  }

  static void _updateRenderParagraph(
    Element element,
    Text widget,
    String translated,
  ) {
    if (element is! RenderObjectElement) {
      // Text widgets create a RichText child which is the RenderObjectElement.
      // We need to find the RenderParagraph in the subtree.
      element.visitChildElements((child) {
        _updateRenderParagraph(child, widget, translated);
      });
      return;
    }

    final renderObject = element.renderObject;
    if (renderObject is RenderParagraph) {
      // Preserve the existing style from the render object (includes
      // DefaultTextStyle merged by the framework). Never fall back to
      // a bare TextStyle() — that would produce white-on-white text.
      final current = renderObject.text;
      final style = current is TextSpan ? current.style : null;
      renderObject.text = TextSpan(text: translated, style: style);
    }
  }
}
