// lib/services/tmdb_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class TmdbService {
  static const String _apiKey = '855e122c79a37991131b7f379919494e';
  static const String _base = 'https://api.themoviedb.org/3';

  // In-memory cache
  static final Map<String, TmdbResult> _cache = {};

  /// Search movies / TV shows
  static Future<List<TmdbResult>> search({
    required String query,
    String? year,
    String type = 'multi', // movie, tv, multi
  }) async {
    final cacheKey = '$type|$query|$year';
    if (_cache.containsKey(cacheKey)) {
      return [_cache[cacheKey]!];
    }

    final url = Uri.parse(
      '$_base/search/$type?api_key=$_apiKey&query=${Uri.encodeComponent(query)}'
      '${year != null ? '&year=$year' : ''}',
    );

    try {
      final resp = await http.get(url);
      if (resp.statusCode != 200) return [];

      final data = jsonDecode(resp.body);
      final results =
          (data['results'] as List? ?? []).cast<Map<String, dynamic>>();

      final out =
          results
              .map(TmdbResult.fromJson)
              .where((r) => r.posterPath != null)
              .toList();

      if (out.isNotEmpty) {
        _cache[cacheKey] = out.first;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Direct poster URL (kept for backward compatibility)
  static Future<String?> getPosterUrl({
    required String title,
    String type = '',
    String? year,
  }) async {
    final results = await search(
      query: title,
      year: year,
      type: type.isEmpty ? 'multi' : type,
    );
    return results.isEmpty ? null : results.first.posterUrl;
  }
}

/// Rich TMDb result
class TmdbResult {
  final String id;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final double? voteAverage;
  final int? voteCount;
  final String? releaseDate; // movie
  final String? firstAirDate; // tv
  final List<String> genres;
  final String mediaType; // movie or tv

  // ADD THIS LINE
  static const String _imgBase = 'https://image.tmdb.org/t/p';

  TmdbResult({
    required this.id,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.voteAverage,
    this.voteCount,
    this.releaseDate,
    this.firstAirDate,
    required this.genres,
    required this.mediaType,
  });

  String get posterUrl => '$_imgBase/w500$posterPath';
  String get backdropUrl => '$_imgBase/w780$backdropPath';
  String get year => (releaseDate ?? firstAirDate ?? '').split('-').first;

  factory TmdbResult.fromJson(Map<String, dynamic> json) {
    final mediaType = json['media_type']?.toString() ?? '';
    final isMovie = mediaType == 'movie';
    final isTv = mediaType == 'tv';

    return TmdbResult(
      id: json['id'].toString(),
      title: (isMovie ? json['title'] : json['name'])?.toString() ?? '',
      originalTitle:
          json['original_title']?.toString() ??
          json['original_name']?.toString(),
      overview: json['overview']?.toString(),
      posterPath: json['poster_path']?.toString(),
      backdropPath: json['backdrop_path']?.toString(),
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      releaseDate: isMovie ? json['release_date']?.toString() : null,
      firstAirDate: isTv ? json['first_air_date']?.toString() : null,
      genres:
          (json['genre_ids'] as List?)?.cast<int>().map(_genreName).toList() ??
          [],
      mediaType: mediaType,
    );
  }

  // Simple genre map – extend as needed
  static String _genreName(int id) {
    const map = {
      28: 'Action',
      12: 'Adventure',
      16: 'Animation',
      35: 'Comedy',
      80: 'Crime',
      99: 'Documentary',
      18: 'Drama',
      10751: 'Family',
      14: 'Fantasy',
      36: 'History',
      27: 'Horror',
      10402: 'Music',
      9648: 'Mystery',
      10749: 'Romance',
      878: 'Sci-Fi',
      10770: 'TV Movie',
      53: 'Thriller',
      10752: 'War',
      37: 'Western',
    };
    return map[id] ?? 'Unknown';
  }
}
