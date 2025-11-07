// lib/widgets/favourite_add_dialogue.dart
import 'package:flutter/material.dart';

import '../services/favourites_service.dart';

Future<String?> _promptNewFolder(BuildContext context) async {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    useRootNavigator: true, // why: avoid nested navigator issues
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
/// Files are fetched and cached immediately via `addFavoriteWithFiles`.
Future<String?> showAddToFavoritesDialog(
  BuildContext context, {
  required FavoriteItem item,
  bool useRootNavigator = true,
}) async {
  // Ensure Hive box is opened before any access.
  await FavoritesService.instance.init();

  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: useRootNavigator,
    builder: (ctx) {
      String? selectedFolder;
      final svc = FavoritesService.instance;

      return StatefulBuilder(
        builder: (ctx, setState) {
          final folders = svc.folders();
          final messenger = ScaffoldMessenger.maybeOf(context);

          return AlertDialog(
            title: const Text('Add to favourites'),
            content: SizedBox(
              width: 440,
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
                      height: 220,
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
                                contains
                                    ? null
                                    : (v) => setState(() => selectedFolder = v),
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
                onPressed:
                    selectedFolder == null
                        ? null
                        : () async {
                          final folder = selectedFolder!;
                          messenger?.showSnackBar(
                            const SnackBar(
                              content: Text('Adding to favourites...'),
                            ),
                          );

                          try {
                            // Service already initialized above.
                            await FavoritesService.instance
                                .addFavoriteWithFiles(
                                  folder: folder,
                                  id: item.id,
                                  title: item.title,
                                  thumb: item.thumb,
                                  url: item.url,
                                  author: item.author,
                                  mediatype: item.mediatype,
                                  formats: item.formats,
                                );

                            messenger?.hideCurrentSnackBar();
                            messenger?.showSnackBar(
                              SnackBar(
                                content: Text('Added to "$folder"'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            messenger?.hideCurrentSnackBar();
                            messenger?.showSnackBar(
                              SnackBar(
                                content: Text('Failed: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, folder);
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
