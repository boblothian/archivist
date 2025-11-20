/// Shared helpers for working with Archive.org resources and responsive grids.
///
/// Keeping these functions in a single location avoids duplicating simple
/// constants and heuristics across multiple screens.
library;

/// Returns the standard Archive.org thumbnail URL for an identifier.
String archiveThumbUrl(String identifier) =>
    'https://archive.org/services/img/$identifier';

/// Returns the fallback thumbnail URL that points directly at the download
/// directory for the identifier.
String archiveFallbackThumbUrl(String identifier) =>
    'https://archive.org/download/$identifier/$identifier.jpg';

/// Heuristic used by several grids in the app to decide how many columns to
/// display based on the available width.
int adaptiveCrossAxisCount(double width) {
  if (width >= 1280) return 6;
  if (width >= 1024) return 5;
  if (width >= 840) return 4;
  if (width >= 600) return 3;
  return 2;
}
