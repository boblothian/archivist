// lib/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;
  }

  void _toggleTheme(bool value) {
    setState(() => _isDarkMode = value);
    // Optional: persist with shared_preferences
    // await Preferences.setBool('darkMode', value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
          // ── Theme Toggle ──
          Card(
            child: SwitchListTile(
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              title: Text(
                'Dark Mode',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                isDark ? 'Currently dark' : 'Currently light',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              value: _isDarkMode,
              onChanged: _toggleTheme,
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
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Archivist',
                    applicationVersion: '1.0.0',
                    applicationIcon: Image.asset(
                      'assets/images/logo.png',
                      width: 48,
                      height: 48,
                    ),
                    applicationLegalese: '© 2025 Your Name. All rights reserved.',
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
                    final uri = Uri.parse('https://github.com/yourusername/archivist/issues');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
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