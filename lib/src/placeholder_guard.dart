/// Protects interpolated variables from being mangled by translation APIs.
///
/// Before sending to API, replaces `{name}`, `$variable`, `{{variable}}`
/// with XML-safe placeholders. After receiving the response, restores them.
class PlaceholderGuard {
  static final _patterns = [
    RegExp(r'\{\{(\w+)\}\}'), // {{variable}}
    RegExp(r'\{(\w+)\}'),     // {variable}
    RegExp(r'\$(\w+)'),       // $variable
  ];

  /// Replaces placeholders with XML-safe tokens.
  ///
  /// Returns a record of `(protected text, list of original placeholders)`.
  static (String, List<String>) protect(String text) {
    final placeholders = <String>[];
    var result = text;

    for (final pattern in _patterns) {
      result = result.replaceAllMapped(pattern, (match) {
        final index = placeholders.length;
        placeholders.add(match.group(0)!);
        return '<x id="ph_$index"/>';
      });
    }

    return (result, placeholders);
  }

  /// Restores original placeholders from XML-safe tokens.
  static String restore(String text, List<String> placeholders) {
    var result = text;
    for (var i = 0; i < placeholders.length; i++) {
      result = result.replaceAll('<x id="ph_$i"/>', placeholders[i]);
    }
    return result;
  }
}
