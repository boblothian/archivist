import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:archivereader/pinned_collections_screen.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:archivereader/widgets/archivist_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // ← STEP 1
import 'package:google_fonts/google_fonts.dart';

import 'collection_search_screen.dart';
import 'collection_store.dart';
import 'favourites_screen.dart';
import 'home_page_screen.dart';
import 'services/favourites_service.dart';
import 'services/theme_controller.dart';
import 'settings_screen.dart';

// ---------- Backgrounds ----------
const _seed = Color(0xFF0B1644);
const kLightBg = Color(0xFFF6F5F2);
const kDarkBg = Color(0xFF0E0E12);

/// STEP 1: Provide a single secure-storage instance using safe iOS accessibility.
/// Use this from your services instead of creating FlutterSecureStorage directly.
class SecureStorage {
  static const instance = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Construct theme controller first (don’t load yet)
  final themeController = ThemeController();

  // Launch immediately — heavy init runs after first frame
  runApp(ArchivistRoot(themeController: themeController));

  // Do heavy work AFTER first frame so iOS doesn’t watchdog-kill us.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await _safeStartup(themeController);
  });
}

/// Handles all delayed startup tasks safely.
Future<void> _safeStartup(ThemeController themeController) async {
  try {
    // If your Favorites/Recent services use secure storage,
    // ensure they use SecureStorage.instance internally.
    await FavoritesService.instance.init().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Optional: log error or reset if corrupted
  }

  try {
    await RecentProgressService.instance.init().timeout(
      const Duration(seconds: 3),
    );
  } catch (_) {
    // Optional: log error
  }

  try {
    await themeController.load().timeout(const Duration(seconds: 2));
  } catch (_) {
    // Optional: fallback to default theme
  }

  // Safe to apply immersive mode after UI exists
  try {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (_) {}
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  ).copyWith(
    background: isDark ? kDarkBg : kLightBg,
    surface: isDark ? const Color(0xFF121217) : Colors.white,
  );

  final inter = GoogleFonts.interTextTheme();
  final merri = GoogleFonts.merriweatherTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    textTheme: inter
        .merge(merri)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    primaryTextTheme: inter.apply(
      bodyColor: scheme.onPrimary,
      displayColor: scheme.onPrimary,
    ),
    iconTheme: IconThemeData(color: scheme.onSurface),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      subtitleTextStyle: inter.bodySmall?.copyWith(
        color: scheme.onSurface.withOpacity(0.75),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceVariant,
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: scheme.onPrimary,
        backgroundColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      hintStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      iconTheme: WidgetStateProperty.all(
        IconThemeData(color: scheme.onSurface),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: scheme.onSurface,
        ),
      ),
    ),
  );
}

class ArchivistRoot extends StatelessWidget {
  const ArchivistRoot({super.key, required this.themeController});
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ThemeControllerProvider(
      controller: themeController,
      child: AnimatedBuilder(
        animation: themeController,
        builder: (_, __) {
          return CollectionsHomeScope(
            notifier: CollectionsHomeState(), // Construct only; load later
            child: MaterialApp(
              title: 'Archivist',
              debugShowCheckedModeBanner: false,
              theme: _buildTheme(Brightness.light),
              darkTheme: _buildTheme(Brightness.dark),
              themeMode: themeController.mode,
              home: AnimatedSplashScreen(
                backgroundColor: kLightBg,
                splash: 'assets/images/logo.png',
                splashIconSize: 300,
                duration: 2500,
                splashTransition: SplashTransition.fadeTransition,
                nextScreen: const RootShell(),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bottom-nav shell
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  static final GlobalKey<_RootShellState> rootKey =
      GlobalKey<_RootShellState>();
  static void switchToTab(int index) => rootKey.currentState?._select(index);
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _keys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  int _current = 0;
  bool _ranLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Run heavy home load after UI exists
    if (!_ranLoad) {
      _ranLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CollectionsHomeScope.of(context)?.load();
      });
    }
  }

  void _select(int i) {
    if (_current == i) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _current = i);
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
      child: PopScope(
        canPop: !(_keys[_current].currentState?.canPop() ?? false),
        onPopInvoked: (didPop) {
          if (didPop) return;
          final nav = _keys[_current].currentState;
          if (nav?.canPop() ?? false) nav!.pop();
        },
        child: Scaffold(
          appBar: const ArchivistAppBar(),
          body: IndexedStack(
            index: _current,
            children: [
              _TabNav(
                navigatorKey: _keys[0],
                builder: (_) => const HomePageScreen(),
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
                builder: (_) => const PinnedCollectionsScreen(),
              ),
              _TabNav(
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
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
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
      ),
    );
  }
}

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
