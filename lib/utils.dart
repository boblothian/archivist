import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ProgressCb = void Function(double progress); // 0.0..1.0

// Single place for HTTP defaults (keeps behavior consistent)
const Map<String, String> kHttpHeaders = {
  'User-Agent': 'ArchiveReader/1.0 (Flutter; +https://archive.org/)',
  'Accept': 'application/json,text/plain,*/*',
  'Accept-Encoding': 'gzip',
};

Future<Directory> appCacheDir() async {
  final dir = await getApplicationCacheDirectory(); // 🚀 Persistent!
  final sub = Directory(p.join(dir.path, 'arch_reader_cache'));
  if (!await sub.exists()) {
    await sub.create(recursive: true);
  }
  return sub;
}

String safeFileName(String input, {int max = 120}) {
  final sanitized = input
      .replaceAll(RegExp(r'[^\w\.-]+', caseSensitive: false), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.length > max ? sanitized.substring(0, max) : sanitized;
}

Future<File> cacheFileForUrl(String url, {String? filenameHint}) async {
  final cache = await appCacheDir();
  final name =
      filenameHint?.trim().isNotEmpty == true
          ? safeFileName(filenameHint!)
          : safeFileName(p.basename(Uri.parse(url).path));
  return File(p.join(cache.path, name));
}

Future<File> downloadWithCache({
  required String url,
  String? filenameHint,
  ProgressCb? onProgress,
  Duration timeout = const Duration(minutes: 2),
  int maxRetries = 2,
}) async {
  final target = await cacheFileForUrl(url, filenameHint: filenameHint);
  if (await target.exists() && (await target.length()) > 0) {
    onProgress?.call(1.0);
    return target;
  }
  return downloadToFile(
    url: url,
    dest: target,
    onProgress: onProgress,
    timeout: timeout,
    maxRetries: maxRetries,
  );
}

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
      final total = res.contentLength ?? 0;
      int received = 0;
      final sink = dest.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(received / total);
        }
      }
      await sink.flush();
      await sink.close();
      onProgress?.call(1.0);
      return dest;
    } catch (e) {
      if (attempt == maxRetries) rethrow;
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
  }
  // unreachable
  throw StateError('downloadToFile failed after retries');
}

Future<String> fetchText(
  String url, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final res = await http
      .get(Uri.parse(url), headers: kHttpHeaders)
      .timeout(timeout);
  if (res.statusCode != 200)
    throw HttpException('GET $url -> ${res.statusCode}');
  // attempt UTF-8, fallback to Latin-1
  try {
    return utf8.decode(res.bodyBytes);
  } catch (_) {
    return latin1.decode(res.bodyBytes);
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void ifMounted(State state, VoidCallback fn) {
  if (state.mounted) fn();
}
