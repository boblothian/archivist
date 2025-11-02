bool isOpenLicensedFromMeta(Map<String, dynamic> meta) {
  // Common Archive.org fields
  final license =
      (meta['license'] ?? meta['licenseurl'] ?? meta['rights'] ?? '')
          .toString()
          .toLowerCase();

  // Quick positives
  const ok = [
    'public domain',
    'pd',
    'cc0',
    'creative commons',
    'cc-by',
    'cc by',
    'cc-by-sa',
    'cc by-sa',
    'cc-by-nd',
    'cc by-nd',
    'cc-by-nc',
    'cc by-nc',
    'cc-by-nc-sa',
    'cc by-nc-sa',
    'cc-by-nc-nd',
    'cc by-nc-nd',
  ];
  if (ok.any((k) => license.contains(k))) return true;

  // Some items mark PD as a flag
  final pdFlag =
      (meta['publicdomain'] ?? meta['pd'] ?? '').toString().toLowerCase();
  if (pdFlag == 'true' || pdFlag == '1' || pdFlag == 'yes') return true;

  // Fallback heuristic: PD-heavy collections (tune as you like)
  final collection = (meta['collection'] ?? '').toString().toLowerCase();
  if (collection.contains('gutenberg') ||
      collection.contains('opensource') ||
      collection.contains('americana') /* adjust to taste */ ) {
    return true;
  }

  return false;
}
