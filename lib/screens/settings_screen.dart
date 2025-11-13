// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_preferences.dart';
import '../theme/app_colours.dart';
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

    // Build colour options list from AppColours.
    final List<_ThemeColorOption> colourOptions = List.generate(
      AppColours.themeSeeds.length,
      (index) => _ThemeColorOption(
        index: index,
        name: AppColours.themeSeedNames[index],
        subtitle: AppColours.themeSeedDescriptions[index],
        color: AppColours.themeSeeds[index],
      ),
    );

    final _ThemeColorOption currentColour = colourOptions.firstWhere(
      (o) => o.index == controller.seedIndex,
      orElse: () => colourOptions.first,
    );

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Mode (original behaviour)
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

          // Theme colour palette selection (now a pop-out)
          Card(
            child: ListTile(
              title: Text(
                'Theme colour',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                currentColour.name,
                style: GoogleFonts.inter(fontSize: 13),
              ),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: currentColour.color,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _showThemeColourPicker(context, controller, colourOptions);
              },
            ),
          ),

          const SizedBox(height: 12),

          // Content Filtering (unchanged)
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _nsfwNotifier,
                  builder: (_, allowNsfw, __) {
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

          // App Actions (unchanged)
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
                    // TODO: hook up real cache-clearing logic.
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

          // Footer version text (unchanged)
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

  // Theme Mode Radio Tiles (unchanged)
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

  void _showThemeColourPicker(
    BuildContext context,
    ThemeController controller,
    List<_ThemeColorOption> options,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Theme colour',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose your accent colour',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ),
              const Divider(height: 1),
              for (int i = 0; i < options.length; i++) ...[
                RadioListTile<int>(
                  value: options[i].index,
                  groupValue: controller.seedIndex,
                  onChanged: (value) {
                    if (value == null) return;
                    controller.setSeedIndex(value);
                    // Update the tile subtitle/swatches above when sheet closes.
                    setState(() {});
                    Navigator.of(sheetContext).pop();
                  },
                  title: Text(
                    options[i].name,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    options[i].subtitle,
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  secondary: CircleAvatar(
                    radius: 14,
                    backgroundColor: options[i].color,
                  ),
                ),
                if (i != options.length - 1) const Divider(height: 1),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeColorOption {
  const _ThemeColorOption({
    required this.index,
    required this.name,
    required this.subtitle,
    required this.color,
  });

  final int index;
  final String name;
  final String subtitle;
  final Color color;
}
