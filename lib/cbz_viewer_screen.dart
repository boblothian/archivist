import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'utils.dart';

class CbzViewerScreen extends StatefulWidget {
  final File cbzFile;
  final String title;

  const CbzViewerScreen({
    super.key,
    required this.cbzFile,
    required this.title,
  });

  @override
  State<CbzViewerScreen> createState() => _CbzViewerScreenState();
}

class _CbzViewerScreenState extends State<CbzViewerScreen> {
  List<File> _images = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cache = await appCacheDir();
      final dir = Directory(
        p.join(cache.path, 'cbz_${widget.cbzFile.path.hashCode}'),
      );
      if (!await dir.exists()) await dir.create(recursive: true);

      final bytes = await widget.cbzFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = <File>[];
      for (final f in archive) {
        if (f.isFile) {
          final name = safeFileName(f.name);
          final file = File(p.join(dir.path, name));
          await file.writeAsBytes(f.content as List<int>, flush: true);
          if (RegExp(
            r'\.(png|jpe?g|webp)$',
            caseSensitive: false,
          ).hasMatch(name)) {
            out.add(file);
          }
        }
      }
      out.sort((a, b) => a.path.compareTo(b.path));
      ifMounted(this, () {
        _images = out;
        _loading = false;
      });
    } catch (e) {
      ifMounted(this, () {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body =
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : PageView.builder(
              itemCount: _images.length,
              itemBuilder:
                  (context, index) =>
                      Image.file(_images[index], fit: BoxFit.contain),
            );

    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }
}
