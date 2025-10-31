import 'package:hive/hive.dart';

class ThumbOverrideService {
  ThumbOverrideService._();
  static final ThumbOverrideService instance = ThumbOverrideService._();

  static const _boxName = 'thumb_overrides';
  Box<String>? _box;

  Future<void> init() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  Future<void> set(String id, String url) async {
    await init();
    await _box!.put(id, url);
  }

  String? get(String id) {
    final b = _box;
    if (b == null) return null;
    return b.get(id);
  }

  Future<void> remove(String id) async {
    await init();
    await _box!.delete(id);
  }

  /// Applies overrides to each map in-place (expects 'identifier' and 'thumb' keys).
  Future<void> applyToItemMaps(List<Map<String, String>> items) async {
    await init();
    for (final m in items) {
      final id = m['identifier'];
      if (id == null) continue;
      final o = _box!.get(id);
      if (o != null && o.trim().isNotEmpty) {
        m['thumb'] = o;
      }
    }
  }
}
