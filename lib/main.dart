// lib/main.dart
import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:archivereader/services/recent_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'collection_search_screen.dart';
import 'favourites_screen.dart';
import 'home_page_screen.dart';
import 'reading_lists_screen.dart';
import 'services/favourites_service.dart';

// ---------- Backgrounds: tweak these ----------
const _seed = Color(0xFF6D1B1B); // sleek indigo accent
const kLightBg = Color(0xFFFFFFFF);
const kDarkBg = Color(0xFF0E0E12);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavoritesService.instance.init();
  await RecentProgressService.instance.init();

  // Immersive mode; overlay icon brightness handled per-screen below
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const ArchivistApp());
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  // Seeded scheme, but force our backgrounds
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  ).copyWith(
    background: isDark ? kDarkBg : kLightBg,
    surface: isDark ? const Color(0xFF121217) : Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,

    // 📖 Typography — Merriweather for headings, Inter for body
    textTheme: TextTheme(
      displayLarge: GoogleFonts.merriweather(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.merriweather(fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.inter(height: 1.5, fontSize: 16),
      bodyMedium: GoogleFonts.inter(height: 1.5, fontSize: 14),
      labelLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),

    // 🧭 AppBar styling
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: GoogleFonts.merriweather(
        fontWeight: FontWeight.w700,
        fontSize: 22,
        color: scheme.onSurface,
      ),
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    ),

    // 🎴 Cards
    cardTheme: CardThemeData(
      elevation: 1,
      margin: const EdgeInsets.all(8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      color: scheme.surface,
    ),

    // 🔘 Buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
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
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    // ✏️ Input Fields
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
      labelStyle: GoogleFonts.inter(color: scheme.onSurfaceVariant),
    ),

    // 📚 Navigation Bar
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    ),
  );
}

class ArchivistApp extends StatelessWidget {
  const ArchivistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Archivist',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: AnimatedSplashScreen(
        // Use theme-aware background for a seamless handoff
        backgroundColor: kLightBg,
        splash: 'assets/images/logo.png',
        splashIconSize: 300,
        duration: 2500,
        splashTransition: SplashTransition.fadeTransition,
        nextScreen: const RootShell(),
      ),
    );
  }
}

/// Simple reusable AppBar that shows your banner logo everywhere.
class ArchivistAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ArchivistAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: SizedBox(
        height: 75,
        child: Image.asset(
          'assets/images/archivist_banner_logo.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
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
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _current = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Keep system icons legible against our themed backgrounds
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
          if (nav?.canPop() ?? false) {
            nav!.pop();
          }
        },
        child: Scaffold(
          appBar: const ArchivistAppBar(),
          body: IndexedStack(
            index: _current,
            children: <Widget>[
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
                builder: (_) => const ReadingListsScreen(),
              ),
              _TabNav(
                navigatorKey: _keys[4],
                builder: (_) => const Placeholder(),
              ), // future Collections hub
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
