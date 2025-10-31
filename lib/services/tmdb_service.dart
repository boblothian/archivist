// services/tmdb_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http;

class TmdbService {
  static const String _apiKey =
      '855e122c79a37991131b7f379919494e'; // Replace with your key
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBaseUrl =
      'https://image.tmdb.org/t/p/w300'; // w300 for thumbs

  /// Search for a movie and return the first matching poster URL
  static Future<String?> getMoviePoster({
    required String title,
    String? year,
  }) async {
    final queryParams = <String, String>{
      'api_key': _apiKey,
      'query': title,
      if (year != null && year.isNotEmpty) 'year': year,
      'language': 'en-US', // Optional: for English results
    };

    final uri = Uri.parse(
      '$_baseUrl/search/movie',
    ).replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final firstResult = results.first as Map<String, dynamic>;
          final posterPath = firstResult['poster_path'] as String?;
          if (posterPath != null && posterPath.isNotEmpty) {
            return '$_imageBaseUrl$posterPath';
          }
        }
      }
    } catch (e) {
      // Silent fail or log error
      print('TMDb movie search error: $e');
    }
    return null;
  }

  /// Search for a TV show and return the first matching poster URL
  static Future<String?> getTvPoster({
    required String title,
    String? year,
  }) async {
    final queryParams = <String, String>{
      'api_key': _apiKey,
      'query': title,
      if (year != null && year.isNotEmpty) 'first_air_date_year': year,
      'language': 'en-US',
    };

    final uri = Uri.parse(
      '$_baseUrl/search/tv',
    ).replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final firstResult = results.first as Map<String, dynamic>;
          final posterPath = firstResult['poster_path'] as String?;
          if (posterPath != null && posterPath.isNotEmpty) {
            return '$_imageBaseUrl$posterPath';
          }
        }
      }
    } catch (e) {
      print('TMDb TV search error: $e');
    }
    return null;
  }

  /// Combined search: Use for movies or TV based on [type]
  static Future<String?> getPosterUrl({
    required String title,
    String? year,
    required String type, // 'movie' or 'tv'
  }) async {
    if (type == 'movie') {
      return getMoviePoster(title: title, year: year);
    } else if (type == 'tv') {
      return getTvPoster(title: title, year: year);
    }
    return null;
  }
}
