import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'translation_cache.dart';
import 'translation_provider.dart';
import 'translator.dart';
import 'tree_scanner.dart';

/// Controls how auto_l10n handles translated text that may break tight layouts.
enum AutoL10nLayoutPolicy {
  /// Disable layout protection and always apply translated strings.
  off,

  /// If translated text does not fit, keep the original source text.
  safeFallback,

  /// If translated text does not fit, trim translated text with ellipsis.
  ///
  /// In unsafe horizontal Row/Flex contexts this uses current text width as
  /// conservative max budget.
  safeEllipsisCurrent,
}

/// Custom binding that hooks into the Flutter rendering pipeline
/// to automatically translate [Text] and [RichText] widgets.
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
  static final Set<TranslationCache> _bootstrapStarted = <TranslationCache>{};
  static final Set<TranslationCache> _bootstrapCompleted = <TranslationCache>{};
  static final Map<TranslationCache, String> _cacheLang = {};
  static AbstractTranslator? _translator;
  static String _sourceLang = 'en';
  static String _targetLang = '';
  static bool _frameCallbackRegistered = false;
  static bool _initialized = false;
  static String? _translationsPath;
  static bool _loadPregenerated = true;
  static AutoL10nLayoutPolicy _layoutPolicy =
      AutoL10nLayoutPolicy.safeEllipsisCurrent;
  static AutoL10nBinding? _instance;

  AutoL10nBinding() {
    _instance = this;
  }

  /// The active translation cache for the current locale, or `null` if source locale.
  static TranslationCache? get cache => _currentCache;

  static TranslationCache? get _currentCache =>
      _isActive ? _cachesByLang[_targetLang] : null;

  /// Whether translation is active (source != target).
  static bool get _isActive => _sourceLang != _targetLang;

  static const String _defaultTranslationsPath = 'assets/auto_l10n';

  /// Initializes the binding.
  ///
  /// Use either [translator] (custom or any [AbstractTranslator]) or
  /// [provider] + optional [apiKey] for a built-in backend.
  /// When both are null and [loadPregenerated] is true, only pre-generated
  /// ARB from [translationsPath] is used (no API).
  /// [targetLocale] is optional and defaults to the device locale.
  /// [sourceLocale] defaults to `en`. When target matches source,
  /// translation is a no-op.
  ///
  /// To clear cache (e.g. for debugging), call [clearCache] before or after init.
  static AutoL10nBinding ensureInitialized({
    AbstractTranslator? translator,
    TranslationProvider? provider,
    String? apiKey,
    String? email,
    String? baseUrl,
    String? translationsPath,
    bool loadPregenerated = true,
    AutoL10nLayoutPolicy layoutPolicy =
        AutoL10nLayoutPolicy.safeEllipsisCurrent,
    Locale? targetLocale,
    Locale sourceLocale = const Locale('en'),
  }) {
    return _doEnsureInitialized(
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
  }

  static AutoL10nBinding _doEnsureInitialized({
    AbstractTranslator? translator,
    TranslationProvider? provider,
    String? apiKey,
    String? email,
    String? baseUrl,
    String? translationsPath,
    bool loadPregenerated = true,
    AutoL10nLayoutPolicy layoutPolicy =
        AutoL10nLayoutPolicy.safeEllipsisCurrent,
    Locale? targetLocale,
    Locale sourceLocale = const Locale('en'),
  }) {
    if (_instance != null) return _instance!;

    final AbstractTranslator? t;
    if (translator != null) {
      t = translator;
    } else if (provider != null) {
      t = createTranslator(
        provider,
        apiKey: apiKey,
        email: email,
        baseUrl: baseUrl,
      );
    } else if (loadPregenerated) {
      t = null; // ARB-only mode: no runtime translator/API.
    } else {
      throw ArgumentError(
        'Either translator or provider must be set, or use loadPregenerated: true with pre-generated ARB.',
      );
    }

    _translator = t;
    _sourceLang = sourceLocale.languageCode;
    final effectiveTarget =
        targetLocale ?? ui.PlatformDispatcher.instance.locale;
    _targetLang = effectiveTarget.languageCode;

    final path = translationsPath ?? _defaultTranslationsPath;
    _translationsPath = path;
    _loadPregenerated = loadPregenerated;
    _layoutPolicy = layoutPolicy;
    // Ensure ServicesBinding exists before SharedPreferences access.
    final existingBinding = _tryGetWidgetsBinding();
    AutoL10nBinding? createdBinding;
    if (existingBinding == null) {
      createdBinding = AutoL10nBinding();
    } else if (existingBinding is AutoL10nBinding) {
      _instance = existingBinding;
    }

    if (_isActive) {
      final c = TranslationCache(
        translator: t,
        targetLang: _targetLang,
        sourceLang: _sourceLang,
      );
      c.addListener(_onTranslationsReady);
      _cachesByLang[_targetLang] = c;
      _cacheLang[c] = _targetLang;
    }

    _initialized = true;
    if (_instance != null) return _instance!;
    if (createdBinding != null) return createdBinding;
    throw StateError(
      'WidgetsBinding is already initialized to ${existingBinding.runtimeType}. '
      'Call autoL10n() before any other binding initialization.',
    );
  }

  static WidgetsBinding? _tryGetWidgetsBinding() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _loadArbAndPreload(
    String basePath,
    String locale,
    TranslationCache cache,
  ) async {
    final normalized = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final assetPath = '$normalized/app_$locale.arb';
    try {
      final raw = await rootBundle.loadString(assetPath);
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final preloaded = <String, String>{};
      for (final e in map.entries) {
        if (e.key.startsWith('@')) continue;
        if (e.value is String) preloaded[e.key] = e.value as String;
      }
      if (preloaded.isNotEmpty) cache.addPreloaded(preloaded);
    } catch (_) {
      // Asset missing or invalid — no preload (e.g. user didn't run generate)
    }
  }

  /// Clears translation cache: SharedPreferences and in-memory.
  /// Call before [ensureInitialized] (e.g. [autoL10n] with [clearCache: true]) or
  /// at runtime to force re-translation. Does not change the current locale.
  static Future<void> clearCache() async {
    if (_instance == null) {
      // Called before autoL10n()/binding init. Nothing to clear safely yet.
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs
          .getKeys()
          .where((x) => x.startsWith('auto_l10n_'))
          .toList()) {
        await prefs.remove(k);
      }
    } catch (e) {
      debugPrint('[auto_l10n] Failed to clear cache: $e');
    }
    for (final c in _cachesByLang.values) {
      c.clearInMemory();
      _bootstrapStarted.remove(c);
      _bootstrapCompleted.remove(c);
    }
    if (_initialized) {
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  /// Switches the target locale at runtime.
  ///
  /// When [locale] matches the source locale, translation becomes a no-op
  /// and original strings are shown. Caches for other locales are kept
  /// so switching back is instant.
  static void setLocale(Locale locale) {
    final translator = _translator;

    _currentCache?.removeListener(_onTranslationsReady);
    _targetLang = locale.languageCode;

    if (_isActive) {
      final c = _cachesByLang[_targetLang] ??= () {
        final cache = TranslationCache(
          translator: translator,
          targetLang: _targetLang,
          sourceLang: _sourceLang,
        );
        _cacheLang[cache] = _targetLang;
        return cache;
      }();
      c.addListener(_onTranslationsReady);
      if (c.canUseTranslator) {
        // Flush after one frame so scan has enqueued; avoids waiting full debounce.
        final langForFlush = _targetLang;
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          _cachesByLang[langForFlush]?.flushPending();
        });
      }
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
      final ready = _ensureBootstrapped(cache);
      // Show what we already have (prefs/ARB) immediately.
      _patchTextWidgets(rootElement);
      // API fallback only after deterministic bootstrap: prefs -> ARB.
      if (ready && cache.canUseTranslator) {
        TreeScanner.scan(rootElement, cache);
      }
    } else {
      // Back to source locale: restore original text in all Text widgets
      _restoreTextWidgets(rootElement);
    }
  }

  static bool _ensureBootstrapped(TranslationCache cache) {
    if (_bootstrapCompleted.contains(cache)) return true;
    if (_bootstrapStarted.contains(cache)) return false;
    _bootstrapStarted.add(cache);

    final locale = _cacheLang[cache] ?? _targetLang;
    final path = _translationsPath;
    Future<void>(() async {
      await cache.loadFromPrefs();
      if (_loadPregenerated && path != null && path.isNotEmpty) {
        await _loadArbAndPreload(path, locale, cache);
      }
      _bootstrapCompleted.add(cache);
      WidgetsBinding.instance.scheduleFrame();
    });
    return false;
  }

  /// When translation is off (source locale), restores original text in all [Text] and [RichText] widgets.
  static void _restoreTextWidgets(Element root) {
    root.visitChildElements((element) {
      final widget = element.widget;
      if (widget is Text) {
        if (widget.data != null) {
          _updateRenderParagraph(element, widget, widget.data!);
        } else if (widget.textSpan != null) {
          _setParagraphSpan(element, widget.textSpan!);
        }
      }
      if (widget is RichText) {
        _setParagraphSpan(element, widget.text);
      }
      _restoreTextWidgets(element);
    });
  }

  /// Walks the element tree and updates RenderParagraph objects with translated text.
  /// Handles both [Text] and [RichText] widgets.
  static void _patchTextWidgets(Element root) {
    final cache = _currentCache;
    if (cache == null) return;

    root.visitChildElements((element) {
      final widget = element.widget;
      if (widget is Text) {
        if (widget.data != null && cache.has(widget.data!)) {
          final translated = cache.translate(widget.data!);
          if (translated != widget.data) {
            _updateRenderParagraph(element, widget, translated);
          }
        } else if (widget.textSpan != null) {
          final translatedSpan = _translateSpan(widget.textSpan!, cache);
          _setParagraphSpan(
            element,
            translatedSpan,
            fallback: widget.textSpan!,
          );
        }
      }
      if (widget is RichText) {
        final translatedSpan = _translateSpan(widget.text, cache);
        _setParagraphSpan(
          element,
          translatedSpan,
          fallback: widget.text,
        );
      }
      _patchTextWidgets(element);
    });
  }

  /// Builds a copy of [span] with TextSpan text replaced by translations where available.
  static InlineSpan _translateSpan(InlineSpan span, TranslationCache cache) {
    if (span is TextSpan) {
      String? newText = span.text;
      if (newText != null && newText.isNotEmpty && cache.has(newText)) {
        newText = cache.translate(newText);
      }
      List<InlineSpan>? newChildren;
      if (span.children != null) {
        newChildren =
            span.children!.map((c) => _translateSpan(c, cache)).toList();
      }
      return TextSpan(
        text: newText,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        onEnter: span.onEnter,
        onExit: span.onExit,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
        children: newChildren ?? span.children,
      );
    }
    return span;
  }

  /// Finds RenderParagraph under [element] and sets its text to [span].
  static void _setParagraphSpan(
    Element element,
    InlineSpan span, {
    InlineSpan? fallback,
  }) {
    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      if (renderObject is RenderParagraph) {
        final fitted = _fitSpanForRenderParagraph(element, renderObject, span);
        if (fitted == null) {
          if (fallback != null) {
            renderObject.text = fallback;
          }
          return;
        }
        renderObject.text = fitted;
        return;
      }
    }
    element.visitChildElements(
      (child) => _setParagraphSpan(child, span, fallback: fallback),
    );
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
      final candidate = TextSpan(text: translated, style: style);
      final fitted =
          _fitSpanForRenderParagraph(element, renderObject, candidate);
      if (fitted == null) {
        final original = widget.data ?? '';
        renderObject.text = TextSpan(text: original, style: style);
        return;
      }
      renderObject.text = fitted;
    }
  }

  static InlineSpan? _fitSpanForRenderParagraph(
    RenderObjectElement element,
    RenderParagraph renderObject,
    InlineSpan candidate,
  ) {
    if (_layoutPolicy == AutoL10nLayoutPolicy.off) {
      return candidate;
    }

    if (_layoutPolicy == AutoL10nLayoutPolicy.safeEllipsisCurrent) {
      if (!_hasUnsafeHorizontalFlexAncestor(element)) {
        // Do not over-constrain normal layouts; this mode only protects tight
        // horizontal Row/Flex labels.
        return candidate;
      }

      final currentWidth = _measureSingleLineWidth(
        renderObject: renderObject,
        span: renderObject.text,
      );
      if (currentWidth != null && currentWidth > 0) {
        final candidateWidth = _measureSingleLineWidth(
          renderObject: renderObject,
          span: candidate,
        );
        if (candidateWidth != null && candidateWidth <= currentWidth) {
          return candidate;
        }
        final truncated = _truncateToFitSingleLine(
          renderObject: renderObject,
          candidate: candidate,
          maxWidth: currentWidth,
        );
        if (truncated != null &&
            _fitsRenderParagraph(renderObject, truncated,
                maxWidth: currentWidth)) {
          return truncated;
        }
        return null;
      }
    }

    final maxWidth = _resolveMaxWidthForParagraph(element, renderObject);
    if (maxWidth == null) return candidate;

    if (_fitsRenderParagraph(renderObject, candidate, maxWidth: maxWidth)) {
      return candidate;
    }

    if (_layoutPolicy == AutoL10nLayoutPolicy.safeFallback) {
      return null;
    }

    // For non-flex children inside horizontal Row/Flex, trim translated text
    // with ellipsis to keep layout stable.
    if (_hasUnsafeHorizontalFlexAncestor(element)) {
      final truncated = _truncateToFitSingleLine(
        renderObject: renderObject,
        candidate: candidate,
        maxWidth: maxWidth,
      );
      if (truncated != null &&
          _fitsRenderParagraph(renderObject, truncated, maxWidth: maxWidth)) {
        return truncated;
      }
    }
    return null;
  }

  static bool _fitsRenderParagraph(
    RenderParagraph renderObject,
    InlineSpan candidate, {
    required double maxWidth,
  }) {
    try {
      if (maxWidth <= 0 || !maxWidth.isFinite) return false;
      final constraints = renderObject.constraints;
      final painter = TextPainter(
        text: candidate,
        textAlign: renderObject.textAlign,
        textDirection: renderObject.textDirection,
        textScaler: renderObject.textScaler,
        maxLines: renderObject.maxLines,
        ellipsis:
            renderObject.overflow == TextOverflow.ellipsis ? '\u2026' : null,
        locale: renderObject.locale,
        strutStyle: renderObject.strutStyle,
        textWidthBasis: renderObject.textWidthBasis,
        textHeightBehavior: renderObject.textHeightBehavior,
      )..layout(
          minWidth: constraints.minWidth,
          maxWidth: maxWidth,
        );

      if (renderObject.maxLines != null && painter.didExceedMaxLines) {
        return false;
      }
      if (!renderObject.softWrap && painter.width > maxWidth) {
        return false;
      }
      return true;
    } catch (e) {
      // If metrics check fails for any reason, prefer keeping prior behavior.
      debugPrint('[auto_l10n] Layout fit-check failed: $e');
      return true;
    }
  }

  static double? _resolveMaxWidthForParagraph(
    RenderObjectElement element,
    RenderParagraph renderObject,
  ) {
    final constraints = renderObject.constraints;
    final directMax = constraints.maxWidth;
    if (directMax.isFinite && directMax > 0) {
      return directMax;
    }

    if (_hasUnsafeHorizontalFlexAncestor(element)) {
      final paintedWidth = renderObject.size.width;
      if (paintedWidth.isFinite && paintedWidth > 0) {
        return paintedWidth;
      }
      // Unsafe horizontal flex without stable current width: cannot safely fit.
      return 0;
    }

    final paintedWidth = renderObject.size.width;
    if (paintedWidth.isFinite && paintedWidth > 0) {
      return paintedWidth;
    }
    return null;
  }

  static bool _hasUnsafeHorizontalFlexAncestor(Element element) {
    var foundHorizontalFlex = false;
    var hasFlexibleWrapper = false;

    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is Flexible || widget is Expanded) {
        hasFlexibleWrapper = true;
      }
      if (widget is Row) {
        foundHorizontalFlex = true;
        return false;
      }
      if (widget is Flex && widget.direction == Axis.horizontal) {
        foundHorizontalFlex = true;
        return false;
      }
      return true;
    });

    return foundHorizontalFlex && !hasFlexibleWrapper;
  }

  static InlineSpan? _truncateToFitSingleLine({
    required RenderParagraph renderObject,
    required InlineSpan candidate,
    required double maxWidth,
  }) {
    final base = candidate is TextSpan ? candidate : null;
    final source = base?.toPlainText(includeSemanticsLabels: false) ?? '';
    if (source.isEmpty) return null;

    final constraints = renderObject.constraints;
    final style = base?.style;
    String build(int len) =>
        len >= source.length ? source : '${source.substring(0, len)}\u2026';

    var low = 0;
    var high = source.length;
    var best = '';

    while (low <= high) {
      final mid = (low + high) >> 1;
      final text = build(mid);
      final probe = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: renderObject.textAlign,
        textDirection: renderObject.textDirection,
        textScaler: renderObject.textScaler,
        maxLines: 1,
        ellipsis: '\u2026',
        locale: renderObject.locale,
        strutStyle: renderObject.strutStyle,
        textWidthBasis: renderObject.textWidthBasis,
        textHeightBehavior: renderObject.textHeightBehavior,
      )..layout(minWidth: constraints.minWidth, maxWidth: maxWidth);

      if (!probe.didExceedMaxLines && probe.width <= maxWidth) {
        best = text;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (best.isEmpty) return null;
    return TextSpan(text: best, style: style);
  }

  static double? _measureSingleLineWidth({
    required RenderParagraph renderObject,
    required InlineSpan span,
  }) {
    try {
      final painter = TextPainter(
        text: span,
        textAlign: renderObject.textAlign,
        textDirection: renderObject.textDirection,
        textScaler: renderObject.textScaler,
        maxLines: 1,
        locale: renderObject.locale,
        strutStyle: renderObject.strutStyle,
        textWidthBasis: renderObject.textWidthBasis,
        textHeightBehavior: renderObject.textHeightBehavior,
      )..layout(minWidth: 0, maxWidth: 1000000);
      return painter.width;
    } catch (_) {
      return null;
    }
  }
}
