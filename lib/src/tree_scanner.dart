import 'package:flutter/widgets.dart';

import 'translation_cache.dart';

/// Walks the element tree after each frame, extracts strings from
/// [Text] and [RichText] widgets, and passes them to [TranslationCache].
class TreeScanner {
  static final _skipPattern = RegExp(r'^[\d\s\$\%\.\,\-\+\/\:]+$');

  /// Scans the element tree starting from [root] and enqueues any
  /// translatable strings into [cache].
  static void scan(Element? root, TranslationCache cache) {
    root?.visitChildElements((element) {
      final widget = element.widget;
      if (widget is Text && widget.data != null) {
        _process(widget.data!, cache);
      }
      if (widget is RichText) {
        _extractSpans(widget.text, cache);
      }
      scan(element, cache); // recurse
    });
  }

  static void _process(String text, TranslationCache cache) {
    if (_shouldSkip(text)) return;
    cache.enqueue(text);
  }

  static void _extractSpans(InlineSpan span, TranslationCache cache) {
    if (span is TextSpan) {
      if (span.text != null) {
        _process(span.text!, cache);
      }
      if (span.children != null) {
        for (final child in span.children!) {
          _extractSpans(child, cache);
        }
      }
    }
  }

  /// Returns `true` if the string should not be translated.
  static bool _shouldSkip(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 2) return true;
    if (_skipPattern.hasMatch(trimmed)) return true;
    // Likely a key, enum value, or route name
    if (!trimmed.contains(' ') && trimmed.length > 25) return true;
    return false;
  }
}
