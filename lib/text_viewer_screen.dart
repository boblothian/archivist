import 'package:flutter/material.dart';

import 'utils.dart';

class TextViewerScreen extends StatefulWidget {
  final String url;
  final String title;

  const TextViewerScreen({super.key, required this.url, required this.title});

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await fetchText(widget.url);
      ifMounted(this, () {
        _content = text;
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
            ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
            : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _content ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            );

    return Scaffold(appBar: AppBar(title: Text(widget.title)), body: body);
  }
}
