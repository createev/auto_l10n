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
  final AbstractTranslator _translator;
  final String _targetLang;
  final String _sourceLang;

  final Map<String, String> _memory = {}; // original → translated
  final Set<String> _pending = {};        // waiting to be sent to API
  bool hasNewTranslations = false;
  Timer? _debounce;

  /// Cache key includes translator type so different translators (e.g. Mock vs MyMemory) don't share cache.
  String get _prefsKey =>
      'auto_l10n_${_translator.runtimeType}_$_targetLang';

  TranslationCache({
    required AbstractTranslator translator,
    required String targetLang,
    String sourceLang = 'en',
  })  : _translator = translator,
        _targetLang = targetLang,
        _sourceLang = sourceLang;

  /// Loads cached translations from SharedPreferences.
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final map = (jsonDecode(raw) as Map).cast<String, String>();
        _memory.addAll(map);
      }
    } catch (e) {
      debugPrint('[auto_l10n] Failed to load cache: $e');
    }
  }

  /// Enqueues a string for translation.
  ///
  /// Strings are collected for 300ms then sent in one batch.
  void enqueue(String original) {
    if (_memory.containsKey(original) || _pending.contains(original)) return;
    _pending.add(original);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _flush);
  }

  /// Sends all pending strings to the translator.
  Future<void> _flush() async {
    if (_pending.isEmpty) return;

    final batch = _pending.toList();
    _pending.clear();

    try {
      final results = await _translator.translateBatch(
        batch,
        targetLang: _targetLang,
        sourceLang: _sourceLang,
      );

      _memory.addAll(results);
      hasNewTranslations = true;
      notifyListeners();

      _saveToPrefs();
    } catch (e) {
      debugPrint('[auto_l10n] Translation error: $e');
      // On error, strings remain untranslated (show original)
    }
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
  String translate(String original) => _memory[original] ?? original;

  /// Whether a translation exists for [original].
  bool has(String original) => _memory.containsKey(original);

  /// All cached translations (for testing/debugging).
  Map<String, String> get translations => Map.unmodifiable(_memory);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
