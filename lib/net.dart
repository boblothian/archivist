import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class Net {
  Net._();
  static final http.Client client = http.Client();

  static const Map<String, String> headers = {
    'User-Agent': 'Archivist/1.0 (Flutter; +https://archive.org/)',
    'Accept': 'application/json,text/plain,*/*',
  };

  static Future<http.Response> get(Uri uri, {Map<String,String>? extra}) {
    final h = {...headers, if (extra != null) ...extra};
    return client.get(uri, headers: h).timeout(const Duration(seconds: 20));
  }

  static Future<http.Response> head(Uri uri, {Map<String,String>? extra}) {
    final h = {...headers, if (extra != null) ...extra};
    return client.head(uri, headers: h).timeout(const Duration(seconds: 20));
  }

  /// Streamed download to a file with proper cleanup and basic status checks.
  static Future<File> downloadTo(
    File outFile,
    Uri uri, {
    Map<String,String>? extra,
    void Function(int received, int? total)? onProgress,
  }) async {
    final req = http.Request('GET', uri);
    req.headers.addAll(headers);
    if (extra != null) req.headers.addAll(extra);
    final res = await req.send().timeout(const Duration(minutes: 2));

    if (res.statusCode != 200) {
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (_) {}
      }
      throw HttpException('HTTP ${res.statusCode}');
    }

    final sink = outFile.openWrite();
    int received = 0;
    final int? total = res.contentLength;

    try {
      await for (final chunk in res.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (onProgress != null) onProgress(received, total);
      }
    } catch (e) {
      try { await sink.flush(); } catch (_) {}
      try { await sink.close(); } catch (_) {}
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (_) {}
      }
      rethrow;
    }

    await sink.flush();
    await sink.close();
    return outFile;
  }
}