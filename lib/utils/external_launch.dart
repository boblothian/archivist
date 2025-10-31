import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches a media file using Android's chooser when available, falling back
/// to the platform default on non-Android platforms.
Future<void> openExternallyWithChooser({
  required String url,
  required String mimeType,
  String chooserTitle = 'Open with',
}) async {
  if (!Platform.isAndroid) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return;
  }

  final viewIntent = AndroidIntent(
    action: 'android.intent.action.VIEW',
    data: url,
    type: mimeType,
    flags: <int>[
      Flag.FLAG_ACTIVITY_NEW_TASK,
      Flag.FLAG_GRANT_READ_URI_PERMISSION,
    ],
  );

  try {
    await viewIntent.launchChooser(chooserTitle);
  } catch (_) {
    final chooserIntent = AndroidIntent(
      action: 'android.intent.action.CHOOSER',
      arguments: <String, dynamic>{
        'android.intent.extra.INTENT': viewIntent,
        'android.intent.extra.TITLE': chooserTitle,
      },
      flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await chooserIntent.launch();
  }
}
