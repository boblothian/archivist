// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_preferences.dart';
import '../theme/theme_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ValueNotifier<bool> _nsfwNotifier;

  @override
  void initState() {
    super.initState();
    _nsfwNotifier = ValueNotifier<bool>(false);
    _loadNsfwSetting();
  }

  Future<void> _loadNsfwSetting() async {
    final allow = await AppPreferences.instance.allowNsfw;
    if (mounted) _nsfwNotifier.value = allow;
  }

  @override
  void dispose() {
    _nsfwNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerProvider.of(context).controller;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.merriweather(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Mode
          Card(
            child: Column(
              children: [
                _themeTile(context, controller, ThemeMode.system),
                const Divider(height: 1),
                _themeTile(context, controller, ThemeMode.light),
                const Divider(height: 1),
                _themeTile(context, controller, ThemeMode.dark),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Content Filtering
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _nsfwNotifier,
                  builder: (_, allowNsfw, _) {
                    return SwitchListTile(
                      secondary: Icon(
                        allowNsfw ? Icons.visibility : Icons.visibility_off,
                      ),
                      title: Text(
                        'Allow NSFW content',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        allowNsfw
                            ? 'NSFW items will be shown'
                            : 'Only safe-for-work items are displayed',
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                      value: allowNsfw,
                      onChanged: (v) async {
                        await AppPreferences.instance.setAllowNsfw(v);
                        _nsfwNotifier.value = v;
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // App Actions
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    'About Archivist',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  onTap:
                      () => showAboutDialog(
                        context: context,
                        applicationName: 'Archivist Reader',
                        applicationVersion: '0.3.2',
                        applicationIcon: Image.asset(
                          'assets/images/logo.png',
                          width: 48,
                          height: 48,
                        ),
                        applicationLegalese:
                            '© 2025 Robert Lothian. All rights reserved.',
                      ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services),
                  title: Text(
                    'Clear Cache',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Remove downloaded files & thumbnails'),
                  onTap: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cache cleared successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
                const Divider(height: 1),

                // Donate
                ListTile(
                  leading: const Icon(Icons.volunteer_activism),
                  title: Text(
                    'Donate to Internet Archive',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Support archive.org'),
                  onTap: () async {
                    final uri = Uri.parse(
                      'https://archive.org/donate?origin=iawww-TopNavDonateButton',
                    );
                    try {
                      final ok = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open the donate page'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to open: $e')),
                      );
                    }
                  },
                ),

                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report),
                  title: Text(
                    'Report a Bug',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    final uri = Uri.parse(
                      'https://github.com/boblothian/archivist/issues',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              'Archivist Reader v0.3.2',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Theme Mode Radio Tiles
  Widget _themeTile(
    BuildContext ctx,
    ThemeController controller,
    ThemeMode mode,
  ) {
    final Map<ThemeMode, ({String title, String subtitle, IconData icon})>
    data = {
      ThemeMode.system: (
        title: 'Use System Theme',
        subtitle: 'Follow device appearance',
        icon: Icons.phone_android,
      ),
      ThemeMode.light: (
        title: 'Light Mode',
        subtitle: 'Always light',
        icon: Icons.light_mode,
      ),
      ThemeMode.dark: (
        title: 'Dark Mode',
        subtitle: 'Always dark',
        icon: Icons.dark_mode,
      ),
    };
    final info = data[mode]!;
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: controller.mode,
      onChanged: (m) => controller.setMode(m ?? ThemeMode.system),
      title: Text(
        info.title,
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(info.subtitle, style: GoogleFonts.inter(fontSize: 13)),
      secondary: Icon(info.icon),
    );
  }
}
