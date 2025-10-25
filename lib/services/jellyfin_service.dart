// lib/jellyfin_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data' as typed_data;

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Configuration for SFTP upload + Jellyfin refresh.
class JellyfinConfig {
  final String sftpHost;
  final int sftpPort;
  final String sftpUser;
  final String sftpPassword; // stored securely

  /// Absolute folder inside a Jellyfin library, e.g. `/media/Movies`
  /// (for Windows SFTP use a folder under your user home, like `/media`,
  /// and symlink it to your actual drive if needed.)
  final String targetLibraryPath;

  /// Jellyfin server (for rescan), e.g. `http://pc:8096`
  final String jellyfinBaseUrl;

  /// Admin or user API key able to refresh library
  final String jellyfinApiKey;

  JellyfinConfig({
    required this.sftpHost,
    required this.sftpPort,
    required this.sftpUser,
    required this.sftpPassword,
    required this.targetLibraryPath,
    required this.jellyfinBaseUrl,
    required this.jellyfinApiKey,
  });

  /// Stored (insecure) part; password is stored separately.
  Map<String, String> toJson() => {
    'sftpHost': sftpHost,
    'sftpPort': sftpPort.toString(),
    'sftpUser': sftpUser,
    'targetLibraryPath': targetLibraryPath,
    'jellyfinBaseUrl': jellyfinBaseUrl,
    'jellyfinApiKey': jellyfinApiKey,
  };

  static JellyfinConfig fromMap(Map<String, String> m, String password) {
    return JellyfinConfig(
      sftpHost: m['sftpHost'] ?? '',
      sftpPort: int.tryParse(m['sftpPort'] ?? '22') ?? 22,
      sftpUser: m['sftpUser'] ?? '',
      sftpPassword: password,
      targetLibraryPath: m['targetLibraryPath'] ?? '',
      jellyfinBaseUrl: m['jellyfinBaseUrl'] ?? '',
      jellyfinApiKey: m['jellyfinApiKey'] ?? '',
    );
  }
}

typedef ProgressCallback = void Function(int sent, int? total);

class JellyfinService {
  JellyfinService._();
  static final JellyfinService instance = JellyfinService._();

  static const _storage = FlutterSecureStorage();
  static const _CONFIG_KEY = 'jellyfin_config_json';
  static const _PASS_KEY = 'jellyfin_sftp_password';

  JellyfinConfig? _cache;

  Future<void> saveConfig(JellyfinConfig cfg) async {
    await _storage.write(key: _CONFIG_KEY, value: jsonEncode(cfg.toJson()));
    await _storage.write(key: _PASS_KEY, value: cfg.sftpPassword);
    _cache = cfg;
  }

  Future<JellyfinConfig?> loadConfig() async {
    if (_cache != null) return _cache;
    final jsonStr = await _storage.read(key: _CONFIG_KEY);
    final pass = await _storage.read(key: _PASS_KEY);
    if (jsonStr == null || pass == null) return null;
    _cache = JellyfinConfig.fromMap(
      Map<String, String>.from(jsonDecode(jsonStr)),
      pass,
    );
    return _cache;
  }

  /// Simple helper to sanitize a filename.
  String _safeFileName(String name) {
    final bad = RegExp(r'[<>:"/\\|?*\n\r\t]');
    final cleaned =
        name.replaceAll(bad, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isEmpty ? 'video' : cleaned;
  }

  /// Build a reasonable destination path for a movie file.
  /// Example: /media/Movies/Some Title (2023)/Some Title (2023).mp4
  String buildMovieDestPath({
    required String targetRoot,
    required String title,
    String? year,
    String extension = 'mp4',
  }) {
    final y = (year == null || year.isEmpty) ? '' : ' ($year)';
    final folder = '${_safeFileName(title)}$y';
    final file = '${_safeFileName(title)}$y.$extension';
    return '$targetRoot/$folder/$file';
  }

  /// Stream a remote URL into SFTP without saving a giant temp file.
  /// If the server gives Content-Length we'll report progress precisely.
  Future<void> uploadFromUrlViaSftp({
    required JellyfinConfig cfg,
    required Uri sourceUrl,
    required String remoteFullPath,
    ProgressCallback? onProgress,
    Map<String, String>? httpHeaders,
  }) async {
    final req = http.Request('GET', sourceUrl);
    if (httpHeaders != null) req.headers.addAll(httpHeaders);
    final resp = await req.send();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode} fetching $sourceUrl');
    }
    final total = resp.contentLength;

    final socket = await SSHSocket.connect(cfg.sftpHost, cfg.sftpPort);
    final client = SSHClient(
      socket,
      username: cfg.sftpUser,
      onPasswordRequest: () => cfg.sftpPassword,
    );

    try {
      final sftp = await client.sftp();

      // mkdir -p for the *parent* directories of the file
      Future<void> ensureParentDirs(String path) async {
        final parts = path.split('/').where((p) => p.isNotEmpty).toList();
        if (parts.isEmpty) return;
        String cur = '';
        // exclude last part (the file name)
        for (int i = 0; i < parts.length - 1; i++) {
          cur += '/${parts[i]}';
          try {
            await sftp.stat(cur);
          } catch (_) {
            try {
              await sftp.mkdir(cur);
            } catch (_) {
              // ignore race/exists
            }
          }
        }
      }

      await ensureParentDirs(remoteFullPath);

      final remoteFile = await sftp.open(
        remoteFullPath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );

      int sent = 0;
      await for (final data in resp.stream) {
        await remoteFile.writeBytes(typed_data.Uint8List.fromList(data));
        sent += data.length;
        onProgress?.call(sent, total);
      }

      // dartssh2's close() returns void → do not await
      remoteFile.close();
      sftp.close();
    } finally {
      client.close();
    }
  }

  /// Call Jellyfin to rescan libraries.
  Future<void> triggerRescan(JellyfinConfig cfg) async {
    final uri = Uri.parse('${cfg.jellyfinBaseUrl}/Library/Refresh');
    final r = await http.post(
      uri,
      headers: {'Authorization': 'MediaBrowser Token=${cfg.jellyfinApiKey}'},
    );
    if (r.statusCode != 204) {
      throw Exception('Refresh failed: ${r.statusCode} ${r.body}');
    }
  }

  /// Create a .strm file (URL pointer) instead of downloading the whole video.
  Future<void> addStreamFromUrl({
    required Uri url,
    required String title,
    JellyfinConfig? config,
  }) async {
    final cfg = config ?? (await loadConfig())!;
    final socket = await SSHSocket.connect(cfg.sftpHost, cfg.sftpPort);
    final client = SSHClient(
      socket,
      username: cfg.sftpUser,
      onPasswordRequest: () => cfg.sftpPassword,
    );

    try {
      final sftp = await client.sftp();

      Future<void> ensureDir(String path) async {
        final parts = path.split('/').where((p) => p.isNotEmpty).toList();
        String cur = '';
        for (int i = 0; i < parts.length; i++) {
          cur += '/${parts[i]}';
          try {
            await sftp.stat(cur);
          } catch (_) {
            try {
              await sftp.mkdir(cur);
            } catch (_) {}
          }
        }
      }

      // Write a single-line file with the URL
      final safeTitle = _safeFileName(title);
      final remoteDir = cfg.targetLibraryPath;
      final remotePath = '$remoteDir/$safeTitle.strm';

      await ensureDir(remoteDir);

      final f = await sftp.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate |
            SftpFileOpenMode.write,
      );
      await f.writeBytes(
        typed_data.Uint8List.fromList('${url.toString()}\n'.codeUnits),
      );
      f.close();
      sftp.close();

      await triggerRescan(cfg);
    } finally {
      client.close();
    }
  }

  /// Convenience: end-to-end operation for a movie link (full copy).
  Future<void> addMovieFromUrl({
    required Uri url,
    required String title,
    String? year,
    String extension = 'mp4',
    Map<String, String>? httpHeaders,
    ProgressCallback? onProgress,
  }) async {
    final cfg = await loadConfig();
    if (cfg == null) {
      throw Exception('Jellyfin not configured');
    }
    final remotePath = buildMovieDestPath(
      targetRoot: cfg.targetLibraryPath,
      title: title,
      year: year,
      extension: extension,
    );
    await uploadFromUrlViaSftp(
      cfg: cfg,
      sourceUrl: url,
      remoteFullPath: remotePath,
      httpHeaders: httpHeaders,
      onProgress: onProgress,
    );
    await triggerRescan(cfg);
  }

  /// First-run / edit config UI.
  Future<JellyfinConfig?> showConfigDialog(BuildContext ctx) async {
    final existing = await loadConfig();
    final sftpHostCtrl = TextEditingController(text: existing?.sftpHost ?? '');
    final sftpPortCtrl = TextEditingController(
      text: (existing?.sftpPort ?? 22).toString(),
    );
    final sftpUserCtrl = TextEditingController(text: existing?.sftpUser ?? '');
    final sftpPassCtrl = TextEditingController(
      text: existing?.sftpPassword ?? '',
    );
    final targetPathCtrl = TextEditingController(
      text: existing?.targetLibraryPath ?? '',
    );
    final jfUrlCtrl = TextEditingController(
      text: existing?.jellyfinBaseUrl ?? '',
    );
    final jfKeyCtrl = TextEditingController(
      text: existing?.jellyfinApiKey ?? '',
    );

    JellyfinConfig? result;

    await showDialog(
      context: ctx,
      builder: (c) {
        return AlertDialog(
          title: const Text('Jellyfin (SFTP) Settings'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: sftpHostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SFTP host (PC/NAS)',
                  ),
                ),
                TextField(
                  controller: sftpPortCtrl,
                  decoration: const InputDecoration(labelText: 'SFTP port'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: sftpUserCtrl,
                  decoration: const InputDecoration(labelText: 'SFTP username'),
                ),
                TextField(
                  controller: sftpPassCtrl,
                  decoration: const InputDecoration(labelText: 'SFTP password'),
                  obscureText: true,
                ),
                TextField(
                  controller: targetPathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target library path (e.g. /media/Movies)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: jfUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Jellyfin Base URL (e.g. http://pc:8096)',
                  ),
                ),
                TextField(
                  controller: jfKeyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Jellyfin API Key',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final cfg = JellyfinConfig(
                  sftpHost: sftpHostCtrl.text.trim(),
                  sftpPort: int.tryParse(sftpPortCtrl.text.trim()) ?? 22,
                  sftpUser: sftpUserCtrl.text.trim(),
                  sftpPassword: sftpPassCtrl.text,
                  targetLibraryPath: targetPathCtrl.text.trim(),
                  jellyfinBaseUrl: jfUrlCtrl.text.trim(),
                  jellyfinApiKey: jfKeyCtrl.text.trim(),
                );
                await saveConfig(cfg);
                result = cfg;
                // ignore: use_build_context_synchronously
                Navigator.pop(c);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    return result ?? existing;
  }
}
