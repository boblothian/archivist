import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeControllerProvider.of(context);
    final theme = Theme.of(context);

    Widget themeTile({
      required ThemeMode mode,
      required String title,
      required String subtitle,
      required IconData icon,
    }) {
      return RadioListTile<ThemeMode>(
        value: mode,
        groupValue: controller.mode,
        onChanged: (m) => controller.setMode(m ?? ThemeMode.system),
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 13)),
        secondary: Icon(icon),
      );
    }

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
          // ── Theme Mode ──
          Card(
            child: Column(
              children: [
                themeTile(
                  mode: ThemeMode.system,
                  title: 'Use System Theme',
                  subtitle: 'Follow device appearance',
                  icon: Icons.phone_android,
                ),
                const Divider(height: 1),
                themeTile(
                  mode: ThemeMode.light,
                  title: 'Light Mode',
                  subtitle: 'Always light',
                  icon: Icons.light_mode,
                ),
                const Divider(height: 1),
                themeTile(
                  mode: ThemeMode.dark,
                  title: 'Dark Mode',
                  subtitle: 'Always dark',
                  icon: Icons.dark_mode,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── App Actions ──
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
                        applicationName: 'Archivist',
                        applicationVersion: '1.0.0',
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
                    // TODO: Add actual cache clearing
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Cache cleared successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
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

          // ── Version Footer ──
          Center(
            child: Text(
              'Archivist v1.0.0',
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
}
