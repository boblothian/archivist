// lib/ui/splash/app_splash_screen.dart
import 'package:animated_splash_screen/animated_splash_screen.dart';
import 'package:flutter/cupertino.dart';

import '../../theme/app_colours.dart' as AppColors;
import '../shell/root_shell.dart';

class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSplashScreen(
      backgroundColor: AppColors.lightBg,
      splash: 'assets/images/logo.png',
      splashIconSize: 300,
      duration: 2500,
      splashTransition: SplashTransition.fadeTransition,
      nextScreen: const RootShell(),
    );
  }
}
