// services/sfw_filter.dart
class SfwFilter {
  // Exact tokens commonly used in Archive.org `subject` metadata for adult content.
  // Keep this tight to avoid false positives.
  static const Set<String> _blockedExact = {
    'nsfw',
    'xxx',
    'hentai',
    'porn',
    'pornography',
    'erotic',
    'erotica',
    'fetish',
    'r18',
    'r-18',
    '18+',
  };

  // Short phrases that show up as subject tags. Avoid super-generic words.
  static const Set<String> _blockedPhrases = {
    'adult only',
    'adult video',
    'adult film',
    'explicit content',
    'sexual content',
  };

  /// Client-side filter: checks **subject metadata** only.
  /// Expects item['subject'] to be a flattened string (comma/semicolon separated).
  static bool isClean(Map<String, String> item) {
    final raw = (item['subject'] ?? '').toLowerCase().trim();
    if (raw.isEmpty) return true;

    // Split typical subject lists: commas, semicolons, pipes, slashes.
    final tokens =
        raw
            .split(RegExp(r'[;,|/]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

    for (final t in tokens) {
      final tok = _normalize(t);
      // Block exact tags like "hentai", "pornography", etc.
      if (_blockedExact.contains(tok)) return false;

      // Block if a token contains one of the short blocked phrases.
      for (final phrase in _blockedPhrases) {
        if (tok.contains(phrase)) return false;
      }

      // Special handling: Don't block generic "adult" alone (too ambiguous).
      // If the token is exactly "adult", we ignore it unless combined with other blocked terms.
      if (tok == 'adult') continue;
    }

    return true;
  }

  /// Server-side exclusion for Archive advancedsearch:
  /// Filter by **subject** only (not title/description) to keep results.
  static String serverExclusionSuffix() {
    // Only use exact/clear tags on the server side.
    final quoted = _blockedExact.map((t) => '"$t"').join(' OR ');
    return ' AND -subject:($quoted)';
  }

  static String _normalize(String s) {
    // lowercase + collapse inner whitespace + strip surrounding punctuation
    final lowered = s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return lowered.replaceAll(RegExp(r'^[^\w+]+|[^\w+]+$'), '');
  }
}
