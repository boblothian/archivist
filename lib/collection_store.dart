// ===================================================================
// File: lib/collection_store.dart
// Shared store for “Pinned Collections”
// ===================================================================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kPinnedCollectionsKey = 'pinned_collections';

class CollectionsHomeState extends ChangeNotifier {
  List<String> _pins = const [];

  List<String> get pins => _pins;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _pins = List.of(prefs.getStringList(kPinnedCollectionsKey) ?? const []);
    notifyListeners();
  }

  bool isPinned(String id) => _pins.contains(id);

  Future<void> pin(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty || _pins.contains(trimmed)) return;
    _pins = List.of(_pins)..add(trimmed);
    await _persist();
  }

  Future<void> unpin(String id) async {
    if (!_pins.contains(id)) return;
    _pins = List.of(_pins)..remove(id);
    await _persist();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex || oldIndex < 0 || newIndex < 0) return;
    final list = List.of(_pins);
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _pins = list;
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kPinnedCollectionsKey, _pins);
    notifyListeners();
  }
}

class CollectionsHomeScope extends InheritedNotifier<CollectionsHomeState> {
  const CollectionsHomeScope({
    super.key,
    required CollectionsHomeState notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static CollectionsHomeState? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CollectionsHomeScope>()
          ?.notifier;
  static CollectionsHomeState of(BuildContext context) => maybeOf(context)!;
}
