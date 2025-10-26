// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'collection_search_screen.dart';
import 'favourites_screen.dart';
import 'home_page_screen.dart';
import 'reading_lists_screen.dart';
import 'services/favourites_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavoritesService.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ArchivistApp());
}

class ArchivistApp extends StatelessWidget {
  const ArchivistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Archivist',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.black,
        brightness: Brightness.light,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      home: const RootShell(),
    );
  }
}

/// Bottom-nav shell with independent navigation stacks per tab.
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  int _current = 0;

  void _select(int i) {
    if (_current == i) {
      // Pop to root of the current tab.
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _current = i);
    }
  }

  Future<bool> _onWillPop() async {
    final canPop = _keys[_current].currentState?.canPop() ?? false;
    if (canPop) {
      _keys[_current].currentState?.pop();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _current,
          children: <Widget>[
            _TabNav(
              navigatorKey: _keys[0],
              builder:
                  (_) => const HomePageScreen(
                    // Optionally provide your real shelf widget:
                    // favoritesShelf: YourFavoritesShelf(),
                  ),
            ),
            _TabNav(
              navigatorKey: _keys[1],
              builder: (_) => const CollectionSearchScreen(),
            ),
            _TabNav(
              navigatorKey: _keys[2],
              builder: (_) => const FavoritesScreen(),
            ),
            _TabNav(
              navigatorKey: _keys[3],
              builder: (_) => const ReadingListsScreen(),
            ),
            // A spare tab (Collections hub) if you add one later.
            _TabNav(
              navigatorKey: _keys[4],
              builder: (_) => const Placeholder(), // TODO: Collections hub
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _current,
          onDestinationSelected: _select,
          destinations: const <NavigationDestination>[
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
              icon: Icon(Icons.list_alt_outlined),
              label: 'Reading',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              label: 'Collections',
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-tab Navigator.
class _TabNav extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final WidgetBuilder builder;
  const _TabNav({required this.navigatorKey, required this.builder, super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute:
          (settings) => MaterialPageRoute(
            builder: (context) => builder(context),
            settings: settings,
          ),
    );
  }
}
