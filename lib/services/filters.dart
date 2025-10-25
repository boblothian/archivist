// Single source of truth for filters
class ArchiveFilters {
  final bool sfwOnly;
  final bool favouritesOnly;
  final bool downloadedOnly;

  const ArchiveFilters({
    this.sfwOnly = false,
    this.favouritesOnly = false,
    this.downloadedOnly = false,
  });

  ArchiveFilters copyWith({
    bool? sfwOnly,
    bool? favouritesOnly,
    bool? downloadedOnly,
  }) {    return ArchiveFilters(
      sfwOnly: sfwOnly ?? this.sfwOnly,
      favouritesOnly: favouritesOnly ?? this.favouritesOnly,
      downloadedOnly: downloadedOnly ?? this.downloadedOnly,
    );
  }
}
