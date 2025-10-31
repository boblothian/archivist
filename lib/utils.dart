import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress callback – receives **bytes received** and **total bytes** (total may be null).
typedef ProgressCb = void Function(double received, int? total);

// ---------------------------------------------------------------------------
// HTTP defaults
// ---------------------------------------------------------------------------
const Map<String, String> kHttpHeaders = {
  'User-Agent': 'ArchiveReader/1.0 (Flutter; +https://archive.org/)',
  'Accept': 'application/json,text/plain,*/*',
  'Accept-Encoding': 'gzip',
};

// ---------------------------------------------------------------------------
// Cache directory
// ---------------------------------------------------------------------------
Future<Directory> appCacheDir() async {
  final dir = await getApplicationCacheDirectory(); // Persistent
  final sub = Directory(p.join(dir.path, 'arch_reader_cache'));
  if (!await sub.exists()) {
    await sub.create(recursive: true);
  }
  return sub;
}

// ---------------------------------------------------------------------------
// Safe file-name helper
// ---------------------------------------------------------------------------
String safeFileName(String input, {int max = 120}) {
  final sanitized = input
      .replaceAll(RegExp(r'[^\w\.-]+', caseSensitive: false), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.length > max ? sanitized.substring(0, max) : sanitized;
}

// ---------------------------------------------------------------------------
// Resolve a cache file for a URL
// ---------------------------------------------------------------------------
Future<File> cacheFileForUrl(String url, {String? filenameHint}) async {
  final cache = await appCacheDir();
  final name =
      filenameHint?.trim().isNotEmpty == true
          ? safeFileName(filenameHint!)
          : safeFileName(p.basename(Uri.parse(url).path));
  return File(p.join(cache.path, name));
}

// ---------------------------------------------------------------------------
// PUBLIC: download with cache + progress
// ---------------------------------------------------------------------------
Future<File> downloadWithCache({
  required String url,
  String? filenameHint,
  ProgressCb? onProgress,
  Duration timeout = const Duration(minutes: 2),
  int maxRetries = 2,
}) async {
  final target = await cacheFileForUrl(url, filenameHint: filenameHint);
  final stopwatch = Stopwatch()..start();

  // -------------------------------------------------
  // Cache hit – return immediately
  // -------------------------------------------------
  if (await target.exists() && (await target.length()) > 0) {
    final sizeMb = (await target.length() / 1024 / 1024).toStringAsFixed(1);
    print('CACHE HIT: ${target.path} (${sizeMb} MB)');
    onProgress?.call(1.0, await target.length());
    return target;
  }

  print('DOWNLOAD START: $url → ${target.path}');
  return downloadToFile(
    url: url,
    dest: target,
    onProgress: (received, total) {
      // ----- calculate percentage & speed -----
      final pct = total != null && total > 0 ? received / total : 0.0;
      final elapsedMs = stopwatch.elapsedMilliseconds;
      final speedMbPerSec =
          total != null && total > 0 && elapsedMs > 0
              ? (received / elapsedMs * 1000 / 1024 / 1024)
              : 0.0;

      print(
        'DOWNLOAD: ${(pct * 100).toStringAsFixed(1)}% | '
        '${(received / 1024 / 1024).toStringAsFixed(1)} MB / '
        '${total != null ? (total / 1024 / 1024).toStringAsFixed(1) : '?'} MB | '
        'Speed: ${speedMbPerSec.toStringAsFixed(2)} MB/s',
      );

      // Pass the *raw* values to the caller (they can compute pct themselves)
      onProgress?.call(received.toDouble(), total);
    },
    timeout: timeout,
    maxRetries: maxRetries,
  );
}

// ---------------------------------------------------------------------------
// Low-level download (http package)
// ---------------------------------------------------------------------------
Future<File> downloadToFile({
  required String url,
  required File dest,
  ProgressCb? onProgress,
  Duration timeout = const Duration(minutes: 2),
  int maxRetries = 2,
}) async {
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll(kHttpHeaders);
      final res = await req.send().timeout(timeout);

      if (res.statusCode != 200) {
        throw HttpException('GET $url -> ${res.statusCode}');
      }

      final total = res.contentLength; // may be null
      var received = 0;
      final sink = dest.openWrite();

      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;

        // Notify caller with raw bytes
        onProgress?.call(received.toDouble(), total);
      }

      await sink.flush();
      await sink.close();
      onProgress?.call(1.0, total);
      return dest;
    } catch (e) {
      if (attempt == maxRetries) rethrow;
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
  }
  // unreachable
  throw StateError('downloadToFile failed after retries');
}

// ---------------------------------------------------------------------------
// Simple text fetch
// ---------------------------------------------------------------------------
Future<String> fetchText(
  String url, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final res = await http
      .get(Uri.parse(url), headers: kHttpHeaders)
      .timeout(timeout);
  if (res.statusCode != 200) {
    throw HttpException('GET $url -> ${res.statusCode}');
  }
  try {
    return utf8.decode(res.bodyBytes);
  } catch (_) {
    return latin1.decode(res.bodyBytes);
  }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void ifMounted(State state, VoidCallback fn) {
  if (state.mounted) fn();
}
