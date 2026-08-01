/// Pure Dart text-to-number extraction used by Text → Math linker routes.
class TextValueExtractor {
  static final RegExp _numberPattern =
      RegExp(r'[-+]?(?:\d+(?:\.\d+)?|\.\d+)');

  static double? extract({
    required String text,
    required String mode,
    int numberIndex = 0,
    String key = '',
  }) {
    switch (mode) {
      case 'whole':
        return double.tryParse(text.trim());
      case 'first':
        return _parseMatch(_numberPattern.firstMatch(text));
      case 'index':
        final matches = _numberPattern.allMatches(text).toList();
        if (numberIndex < 0 || numberIndex >= matches.length) return null;
        return _parseMatch(matches[numberIndex]);
      case 'key':
        final normalizedKey = key.trim();
        if (normalizedKey.isEmpty) return null;
        final pattern = RegExp(
          '${RegExp.escape(normalizedKey)}\\s*[：:=]\\s*(${_numberPattern.pattern})',
          caseSensitive: false,
        );
        final match = pattern.firstMatch(text);
        return match == null ? null : double.tryParse(match.group(1)!);
      default:
        return null;
    }
  }

  static double? _parseMatch(RegExpMatch? match) =>
      match == null ? null : double.tryParse(match.group(0)!);
}
