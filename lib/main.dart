import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_page_screen.dart';
import 'services/favourites_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavoritesService.instance.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(const ArchiveReaderApp());
}

class ArchiveReaderApp extends StatelessWidget {
  const ArchiveReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Archive Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const HomePageScreen(),
    );
  }
}
