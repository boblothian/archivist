// lib/ui/shell/root_shell.dart
import 'package:archivereader/collection_store.dart'; // Singleton store
import 'package:archivereader/ui/shell/tab_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/collection_search_screen.dart';
import '../../screens/favourites_screen.dart';
import '../../screens/home_page_screen.dart';
import '../../screens/pinned_collections_screen.dart';
import '../../screens/settings_screen.dart';
import '../../widgets/archivist_app_bar.dart';

/// ---------------------------------------------------------------
/// Public entry point – switch tabs from anywhere in the app
/// ---------------------------------------------------------------
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  /// Call this from anywhere to switch tabs
  static void switchToTab(int index) {
    _rootKey.currentState?._select(index);
  }

  /// Global key to access state
  static final GlobalKey<RootShellState> _rootKey = GlobalKey<RootShellState>();

  @override
  State<RootShell> createState() => RootShellState();
}

/// ---------------------------------------------------------------
/// State – handles tab switching and lazy loading
/// ---------------------------------------------------------------
class RootShellState extends State<RootShell> {
  final List<GlobalKey<NavigatorState>> _keys = List.generate(
    5,
    (_) => GlobalKey<NavigatorState>(),
  );
  int _current = 0;
  bool _ranStartupLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Load pinned IDs once at startup (tiny, main thread)
    if (!_ranStartupLoad) {
      _ranStartupLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CollectionStore().loadPinned(); // Direct singleton access
      });
    }
  }

  /// Internal tab selection
  void _select(int index) {
    if (_current == index) {
      // Pop to root of current tab
      _keys[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _current = index);

      // Collections tab (index 3) → load local files in isolate
      if (index == 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          CollectionStore().loadLocal('/storage/emulated/0/Collections');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        appBar: const ArchivistAppBar(),
        body: IndexedStack(
          index: _current,
          children: [
            // Home
            TabNav(
              navigatorKey: _keys[0],
              builder: (_) => const HomePageScreen(),
            ),
            // Search
            TabNav(
              navigatorKey: _keys[1],
              builder: (_) => const CollectionSearchScreen(),
            ),
            // Favourites
            TabNav(
              navigatorKey: _keys[2],
              builder: (_) => const FavoritesScreen(),
            ),
            // Collections (local + pinned)
            TabNav(
              navigatorKey: _keys[3],
              builder: (_) => const PinnedCollectionsScreen(),
            ),
            // Settings
            TabNav(
              navigatorKey: _keys[4],
              builder: (_) => const SettingsScreen(),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            indicatorColor: Theme.of(context).colorScheme.primaryContainer,
            selectedIndex: _current,
            onDestinationSelected: _select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(
                icon: Icon(Icons.favorite_outline),
                label: 'Favourites',
              ),
              NavigationDestination(
                icon: Icon(Icons.collections_bookmark_outlined),
                label: 'Collections',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
