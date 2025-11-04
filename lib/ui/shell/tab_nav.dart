// lib/ui/shell/tab_nav.dart
import 'package:flutter/material.dart';

/// A per-tab Navigator that preserves state across tab switches.
///
/// Used inside an [IndexedStack] to give each tab its own navigation stack.
class TabNav extends StatelessWidget {
  /// The key for this tab's Navigator — must be unique per tab.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Builder that returns the root page for this tab.
  final WidgetBuilder builder;

  const TabNav({required this.navigatorKey, required this.builder, super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (RouteSettings settings) {
        return MaterialPageRoute(settings: settings, builder: builder);
      },
    );
  }
}
