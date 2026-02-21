import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translator.dart';

/// Central store for all translations.
///
/// Collects strings via [enqueue], debounces for 300ms, then sends a batch
/// to the translator. Results are cached in memory and persisted to
/// SharedPreferences.
class TranslationCache extends ChangeNotifier {
  static const List<int> _retryDelaysSeconds = [1, 2, 3];
  static final RegExp _multiWhitespace = RegExp(r'\s+');

  final AbstractTranslator? _translator;
  final String _targetLang;
  final String _sourceLang;

  final Map<String, String> _memory = {}; // original → translated
  final Map<String, String> _normalizedKeyIndex = {}; // normalized -> original
  final Set<String> _pending = {}; // waiting to be sent to API
  bool hasNewTranslations = false;
  Timer? _debounce;
  Timer? _retryTimer;
  bool _isFlushing = false;
  int _retryAttempt = 0;
  bool _gaveUpCurrentBatch = false;

  /// Unified cache key per language.
  String get _prefsKey => 'auto_l10n_$_targetLang';

  TranslationCache({
    AbstractTranslator? translator,
    required String targetLang,
    String sourceLang = 'en',
    Map<String, String>? preloaded,
  })  : _translator = translator,
        _targetLang = targetLang,
        _sourceLang = sourceLang {
    if (preloaded != null && preloaded.isNotEmpty) {
      for (final e in preloaded.entries) {
        if (e.value != e.key) {
          _memory[e.key] = e.value;
          _indexLookupKey(e.key);
        }
      }
    }
  }

  bool get canUseTranslator => _translator != null;

  /// Adds preloaded translations (e.g. from ARB) after creation.
  /// Used when loading from assets completes asynchronously.
  void addPreloaded(Map<String, String> map) {
    if (map.isEmpty) return;
    for (final e in map.entries) {
      if (e.value != e.key) {
        _memory[e.key] = e.value;
        _indexLookupKey(e.key);
      }
    }
    hasNewTranslations = true;
    notifyListeners();
  }

  /// Loads cached translations from SharedPreferences.
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).cast<String, String>();
        // Do not overwrite already-loaded values (e.g. fresh ARB preload).
        // This avoids stale SharedPreferences data winning in load-order races.
        map.forEach((k, v) {
          if (v != k) {
            _memory.putIfAbsent(k, () => v);
            _indexLookupKey(k);
          }
        });
      }
    } catch (e) {
      debugPrint('[auto_l10n] Failed to load cache: $e');
    }
  }

  /// Enqueues a string for translation.
  ///
  /// Strings are collected for 300ms then sent in one batch.
  void enqueue(String original) {
    if (_translator == null) return;
    if (_memory.containsKey(original) || _pending.contains(original)) return;
    _pending.add(original);
    if (_gaveUpCurrentBatch) {
      // New input unlocks retries for a new batch.
      _gaveUpCurrentBatch = false;
      _retryAttempt = 0;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _flush);
  }

  /// Flushes pending strings immediately (e.g. after locale switch).
  void flushPending() {
    if (_translator == null) return;
    _debounce?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _gaveUpCurrentBatch = false;
    _retryAttempt = 0;
    _flush();
  }

  /// Sends all pending strings to the translator.
  Future<void> _flush() async {
    if (_isFlushing || _pending.isEmpty) return;
    final translator = _translator;
    if (translator == null) return;
    _isFlushing = true;

    final batch = _pending.toList();
    _pending.clear();

    try {
      final results = await translator.translateBatch(
        batch,
        targetLang: _targetLang,
        sourceLang: _sourceLang,
      );

      var changed = false;
      results.forEach((k, v) {
        if (v == k) return;
        final previous = _memory[k];
        if (previous != v) {
          _memory[k] = v;
          _indexLookupKey(k);
          changed = true;
        }
      });
      if (changed) {
        hasNewTranslations = true;
        notifyListeners();
      }
      _retryAttempt = 0;
      _gaveUpCurrentBatch = false;
      _retryTimer?.cancel();
      _retryTimer = null;

      if (changed) {
        _saveToPrefs();
      }
    } catch (e) {
      debugPrint('[auto_l10n] Translation error: $e');
      // Re-queue failed batch so temporary API failures don't freeze text forever.
      _pending.addAll(batch.where((s) => !_memory.containsKey(s)));
      _scheduleRetry();
    } finally {
      _isFlushing = false;
    }
  }

  void _scheduleRetry() {
    if (_pending.isEmpty) return;
    if (_retryTimer != null && _retryTimer!.isActive) return;
    if (_gaveUpCurrentBatch) return;

    if (_retryAttempt >= _retryDelaysSeconds.length) {
      _gaveUpCurrentBatch = true;
      debugPrint(
        '[auto_l10n] Gave up after ${_retryDelaysSeconds.length} retry attempts.',
      );
      return;
    }

    final delaySeconds = _retryDelaysSeconds[_retryAttempt];
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      _retryTimer = null;
      _flush();
    });
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_memory));
    } catch (e) {
      debugPrint('[auto_l10n] Failed to save cache: $e');
    }
  }

  /// Returns the translated string, or the original if not yet translated.
  String translate(String original) {
    final direct = _memory[original];
    if (direct != null && direct != original) return direct;

    final matchedKey = _findLookupKey(original);
    if (matchedKey == null) return direct ?? original;

    var translated = _memory[matchedKey] ?? original;
    if (translated == original && direct != null) return direct;

    // Preserve style when lookup matched by normalized/case-insensitive key.
    if (matchedKey != original) {
      translated = _applyCasePattern(
        source: original,
        translated: translated,
      );
    }

    return _applyOuterWhitespace(source: original, translated: translated);
  }

  /// Whether a translation exists for [original].
  bool has(String original) {
    final direct = _memory[original];
    if (direct != null && direct != original) return true;
    return _findLookupKey(original) != null;
  }

  /// All cached translations (for testing/debugging).
  Map<String, String> get translations => Map.unmodifiable(_memory);

  /// Clears in-memory state only. Used by [AutoL10nBinding.clearCache].
  void clearInMemory() {
    _memory.clear();
    _normalizedKeyIndex.clear();
    _pending.clear();
    _debounce?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
    _isFlushing = false;
    _retryAttempt = 0;
    _gaveUpCurrentBatch = false;
    hasNewTranslations = false;
    notifyListeners();
  }

  void _indexLookupKey(String key) {
    final normalized = _normalizeLookupKey(key);
    if (normalized.isNotEmpty) {
      _normalizedKeyIndex.putIfAbsent(normalized, () => key);
    }
  }

  String? _findLookupKey(String original) {
    final trimmed = original.trim();
    final trimmedDirect = _memory[trimmed];
    if (trimmedDirect != null && trimmedDirect != original) return trimmed;

    final normalized = _normalizeLookupKey(original);
    final normalizedKey = _normalizedKeyIndex[normalized];
    if (normalizedKey != null) {
      final normalizedValue = _memory[normalizedKey];
      if (normalizedValue != null && normalizedValue != original) {
        return normalizedKey;
      }
    }
    return null;
  }

  String _normalizeLookupKey(String input) =>
      input.trim().replaceAll(_multiWhitespace, ' ').toLowerCase();

  String _applyCasePattern({
    required String source,
    required String translated,
  }) {
    final sourceTrimmed = source.trim();
    if (!_hasCase(sourceTrimmed)) return translated;

    if (sourceTrimmed == sourceTrimmed.toUpperCase()) {
      return translated.toUpperCase();
    }
    if (sourceTrimmed == sourceTrimmed.toLowerCase()) {
      return translated.toLowerCase();
    }
    return translated;
  }

  bool _hasCase(String value) => value.toLowerCase() != value.toUpperCase();

  String _applyOuterWhitespace({
    required String source,
    required String translated,
  }) {
    final leadingLen = source.length - source.trimLeft().length;
    final trailingLen = source.length - source.trimRight().length;
    if (leadingLen == 0 && trailingLen == 0) return translated;

    final leading = leadingLen > 0 ? source.substring(0, leadingLen) : '';
    final trailing =
        trailingLen > 0 ? source.substring(source.length - trailingLen) : '';
    return '$leading$translated$trailing';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
