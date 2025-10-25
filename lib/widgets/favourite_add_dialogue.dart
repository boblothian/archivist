import 'package:flutter/material.dart';

import '../services/favourites_service.dart';

Future<String?> _promptNewFolder(BuildContext context) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('New favourites folder'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. Movies, Comics'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
  );
}

/// Shows the "Add to favourites" dialog and returns the folder name if added.
Future<String?> showAddToFavoritesDialog(
  BuildContext context, {
  required FavoriteItem item,
}) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      String? selectedFolder;
      // Use a single StatefulBuilder around the WHOLE dialog to keep it simple/reliable.
      return StatefulBuilder(
        builder: (ctx, setState) {
          final svc = FavoritesService.instance;
          final folders = svc.folders();

          return AlertDialog(
            title: const Text('Add to favourites'),
            // Avoid IntrinsicWidth on a viewport: give the list a fixed height via SizedBox.
            content: SizedBox(
              width: 440, // safe fixed width; dialog will clamp on phones
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (folders.isEmpty)
                    const ListTile(
                      dense: true,
                      title: Text('No folders yet'),
                      subtitle: Text('Create your first folder below.'),
                    ),
                  if (folders.isNotEmpty)
                    SizedBox(
                      height:
                          220, // <-- key: fixed height list to avoid intrinsic sizing
                      child: ListView.separated(
                        shrinkWrap: true,
                        primary: false,
                        itemCount: folders.length,
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemBuilder: (_, i) {
                          final f = folders[i];
                          final contains = svc.contains(f, item.id);
                          return RadioListTile<String>(
                            title: Text(f),
                            subtitle:
                                contains
                                    ? const Text('Already contains this item')
                                    : null,
                            value: f,
                            groupValue: selectedFolder,
                            onChanged:
                                (v) => setState(() => selectedFolder = v),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Create new folder'),
                      onPressed: () async {
                        final name = await _promptNewFolder(context);
                        if (name == null || name.isEmpty) return;
                        if (!svc.folderExists(name)) {
                          await svc.createFolder(name);
                        }
                        // Rebuild to show the new folder and preselect it.
                        setState(() => selectedFolder = name);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (selectedFolder == null) return;
                  await FavoritesService.instance.addToFolder(
                    selectedFolder!,
                    item,
                  );
                  // ignore: use_build_context_synchronously
                  Navigator.pop(ctx, selectedFolder);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}
