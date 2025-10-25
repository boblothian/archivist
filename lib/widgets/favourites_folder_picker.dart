import 'package:flutter/material.dart';

import '../services/favourites_service.dart';

Future<String?> showFavoriteFolderPicker(BuildContext context) async {
  final svc = FavoritesService.instance;
  final controller = TextEditingController();
  String? selected;

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final folders = svc.folders();
      return AlertDialog(
        title: const Text('Add to favourites'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (folders.isNotEmpty)
              SizedBox(
                height: 200,
                width: 360,
                child: ListView.builder(
                  itemCount: folders.length,
                  itemBuilder: (_, i) {
                    final f = folders[i];
                    return RadioListTile<String>(
                      title: Text(f),
                      value: f,
                      groupValue: selected,
                      onChanged: (v) {
                        selected = v;
                        (ctx as Element).markNeedsBuild();
                      },
                    );
                  },
                ),
              ),
            const Divider(),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Or create new folder',
                hintText: 'e.g. Movies, Comics',
              ),
              onSubmitted: (_) {}, // just close on action button
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              var folder = selected;
              final newName = controller.text.trim();
              if (folder == null && newName.isNotEmpty) {
                await svc.createFolder(newName);
                folder = newName;
              }
              if (folder != null) {
                Navigator.pop(ctx, folder);
              }
            },
            child: const Text('Add'),
          ),
        ],
      );
    },
  );
}
