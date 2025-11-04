// lib/services/collections_loader.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p; // ← Alias it!

/// -----------------------------------------------------------------
/// Model for a comic/archive collection
/// -----------------------------------------------------------------
class Collection {
  final String id; // Full file path (unique)
  final String title; // Display name
  final String path; // Full path
  final String extension; // .cbz, .cbr, .pdf

  Collection({
    required this.id,
    required this.title,
    required this.path,
    required this.extension,
  });

  /// Create from file path
  factory Collection.fromFile(File file) {
    final ext = p.extension(file.path).toLowerCase(); // ← Use alias
    final name = p.basenameWithoutExtension(file.path); // ← Use alias
    return Collection(
      id: file.path,
      title: name,
      path: file.path,
      extension: ext,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Collection && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// -----------------------------------------------------------------
/// TOP-LEVEL FUNCTION — REQUIRED for compute()
/// Runs in background isolate
/// -----------------------------------------------------------------
Future<List<Collection>> loadCollectionsIsolated(String rootPath) async {
  final dir = Directory(rootPath);
  final collections = <Collection>[];

  if (!await dir.exists()) {
    debugPrint('Collections directory not found: $rootPath');
    return collections;
  }

  final supported = <String>{'.cbz', '.cbr', '.pdf', '.epub'};

  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      final ext = p.extension(entity.path).toLowerCase(); // ← Use alias
      if (supported.contains(ext)) {
        collections.add(Collection.fromFile(entity));
      }
    }
  }

  debugPrint('Found ${collections.length} collections');
  return collections;
}
