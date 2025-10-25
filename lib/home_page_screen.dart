// lib/screens/home_page_screen.dart
import 'dart:async';

import 'package:archivereader/services/favourites_service.dart'; // <-- ADDED
import 'package:archivereader/services/filters.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_detail_screen.dart';
import 'favourites_screen.dart';

enum Category { classic, books, magazines, comics, video, readingList }

extension CategoryX on Category {
  String get label {
    switch (this) {
      case Category.classic:
        return 'Classic Literature';
      case Category.books:
        return 'Books';
      case Category.magazines:
        return 'Magazines';
      case Category.comics:
        return 'Comics';
      case Category.video:
        return 'Videos';
      case Category.readingList:
        return 'Reading Lists';
    }
  }

  IconData get icon {
    switch (this) {
      case Category.classic:
        return Icons.menu_book_outlined;
      case Category.books:
        return Icons.library_books_outlined;
      case Category.magazines:
        return Icons.article_outlined;
      case Category.comics:
        return Icons.auto_awesome_mosaic_outlined;
      case Category.video:
        return Icons.local_movies_outlined;
      case Category.readingList:
        return Icons.bookmarks_outlined;
    }
  }
}

class HomePageScreen extends StatefulWidget {
  const HomePageScreen({super.key});

  @override
  State<HomePageScreen> createState() => _HomePageScreenState();
}

class _HomePageScreenState extends State<HomePageScreen> with RouteAware {
  // Quick filters (persisted)
  static const _kSfw = 'home_sfw';
  static const _kFav = 'home_fav';
  static const _kDld = 'home_dld';

  bool _sfwOnly = false;
  bool _favouritesOnly = false;
  bool _downloadedOnly = false;

  // Pinned collections
  static const _pinsKey = 'pinned_collections';
  List<String> _pinned = [];

  ArchiveFilters get _filters => ArchiveFilters(
    sfwOnly: _sfwOnly,
    favouritesOnly: _favouritesOnly,
    downloadedOnly: _downloadedOnly,
  );

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadPins();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sfwOnly = prefs.getBool(_kSfw) ?? false;
      _favouritesOnly = prefs.getBool(_kFav) ?? false;
      _downloadedOnly = prefs.getBool(_kDld) ?? false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSfw, _sfwOnly);
    await prefs.setBool(_kFav, _favouritesOnly);
    await prefs.setBool(_kDld, _downloadedOnly);
  }

  Future<void> _loadPins() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    setState(() => _pinned = List.of(list));
  }

  Future<void> _addPin(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    if (list.contains(trimmed)) return;
    final updated = List.of(list)..add(trimmed);
    await prefs.setStringList(_pinsKey, updated);
    setState(() => _pinned = updated);
  }

  Future<void> _removePin(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    final updated = List.of(list)..remove(id);
    await prefs.setStringList(_pinsKey, updated);
    setState(() => _pinned = updated);
  }

  Future<void> _reorderPins(int oldIndex, int newIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pinsKey) ?? const <String>[];
    final pins = List.of(list);
    if (oldIndex < newIndex) newIndex -= 1;
    final item = pins.removeAt(oldIndex);
    pins.insert(newIndex, item);
    await prefs.setStringList(_pinsKey, pins);
    setState(() => _pinned = pins);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 980;

        return Scaffold(
          drawer:
              wide
                  ? null
                  : _AppDrawer(
                    sfwOnly: _sfwOnly,
                    onToggleSfw:
                        (v) => setState(() {
                          _sfwOnly = v;
                          _savePrefs();
                        }),
                    onOpenExplore: _openExplore,
                  ),
          appBar: AppBar(
            title: const Text('Archivist'),
            actions: [
              IconButton(
                tooltip: 'Search collections',
                icon: const Icon(Icons.travel_explore),
                onPressed: _openExplore,
              ),
              IconButton(
                tooltip: 'Search items',
                icon: const Icon(Icons.search),
                onPressed: _openSearch,
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _FilterBar(
                sfwOnly: _sfwOnly,
                favouritesOnly: _favouritesOnly,
                downloadedOnly: _downloadedOnly,
                onChanged: (s, f, d) {
                  setState(() {
                    _sfwOnly = s;
                    _favouritesOnly = f;
                    _downloadedOnly = d;
                  });
                  _savePrefs();
                },
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _onAddCollection,
            icon: const Icon(Icons.add),
            label: const Text('Add collection'),
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _CategoriesStrip(onTap: _openCategory)),

              if (_pinned.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'My Collections',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _openManagePins,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Manage'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_pinned.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: _PinnedGrid(
                    ids: _pinned,
                    onOpen: (id) => _openCollectionById(id),
                    onRemove: (id) => _removePin(id),
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Popular picks',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: _PopularGrid(onOpen: (id) => _openCollectionById(id)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 84)),
            ],
          ),
        );
      },
    );
  }

  // ---- Navigation

  void _openSearch() {
    showSearch(context: context, delegate: _SimpleSearchDelegate(_filters));
  }

  Future<void> _openExplore() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ExploreCollectionsScreen(onPinnedChanged: () => _loadPins()),
      ),
    );
    await _loadPins();
  }

  void _openManagePins() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ManagePinsScreen(
              ids: _pinned,
              onReorder: _reorderPins,
              onRemove: _removePin,
            ),
      ),
    );
    await _loadPins();
  }

  void _openCollectionById(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
              categoryName: id,
              collectionName: id,
              filters: _filters,
            ),
      ),
    );
  }

  void _onAddCollection() {
    final parentContext = context;

    showModalBottomSheet(
      context: parentContext,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        void openCollection(String id) async {
          await _addPin(id);
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _openCollectionById(id);
          });
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(Icons.collections_bookmark_outlined),
                title: Text('Add a popular Archive.org collection'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _ChipButton(
                    label: 'internetarchivebooks',
                    onTap: () => openCollection('internetarchivebooks'),
                  ),
                  _ChipButton(
                    label: 'opensource',
                    onTap: () => openCollection('opensource'),
                  ),
                  _ChipButton(
                    label: 'classicpcgames',
                    onTap: () => openCollection('classicpcgames'),
                  ),
                  _ChipButton(
                    label: 'computer_magazines',
                    onTap: () => openCollection('computer_magazines'),
                  ),
                  _ChipButton(
                    label: 'videogamemagazines',
                    onTap: () => openCollection('videogamemagazines'),
                  ),
                  _ChipButton(
                    label: 'pulpmagazinearchive',
                    onTap: () => openCollection('pulpmagazinearchive'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Collection identifier',
                  hintText: 'e.g. comics_inbox',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (id) {
                  final trimmed = id.trim();
                  if (trimmed.isEmpty) return;
                  openCollection(trimmed);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openExplore();
                  },
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Explore collections'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _openCategory(Category c) {
    switch (c) {
      case Category.readingList:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReadingListScreen()),
        );
        break;
      case Category.magazines:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MagazinesHubScreen(filters: _filters),
          ),
        );
        break;
      case Category.classic:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Classic Literature',
                  customQuery:
                      'collection:internetarchivebooks AND (title:classic OR subject:("Classic" OR "Literature"))',
                  filters: _filters,
                ),
          ),
        );
        break;
      case Category.books:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Books',
                  collectionName: 'internetarchivebooks',
                  filters: _filters,
                ),
          ),
        );
        break;
      case Category.comics:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Comics',
                  collectionName: 'comics',
                  filters: _filters,
                ),
          ),
        );
        break;
      case Category.video:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CollectionDetailScreen(
                  categoryName: 'Videos',
                  collectionName: 'opensource_movies',
                  filters: _filters,
                ),
          ),
        );
        break;
    }
  }
}

// ---------------------------------------------------------------------
// DRAWER – ONLY ONE DEFINITION
// ---------------------------------------------------------------------
class _AppDrawer extends StatelessWidget {
  final bool sfwOnly;
  final ValueChanged<bool> onToggleSfw;
  final VoidCallback? onOpenExplore;

  const _AppDrawer({
    required this.sfwOnly,
    required this.onToggleSfw,
    this.onOpenExplore,
  });

  @override
  Widget build(BuildContext context) {
    final svc = FavoritesService.instance;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Archivist',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ),

            // SFW toggle
            SwitchListTile(
              title: const Text('SFW Mode'),
              value: sfwOnly,
              onChanged: onToggleSfw,
              secondary: const Icon(Icons.shield_moon_outlined),
            ),

            // Explore collections
            ListTile(
              leading: const Icon(Icons.travel_explore),
              title: const Text('Explore collections'),
              onTap: () {
                Navigator.pop(context);
                onOpenExplore?.call();
              },
            ),

            const Divider(),

            // FAVOURITES SECTION
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Favourites',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),

            ValueListenableBuilder<int>(
              valueListenable: svc.version,
              builder: (context, _, __) {
                final folders = svc.folders();

                if (folders.isEmpty) {
                  return const ListTile(
                    leading: Icon(Icons.favorite_border),
                    title: Text('No folders yet'),
                    subtitle: Text('Create your first folder below.'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: folders.length,
                  itemBuilder: (context, i) {
                    final folderName = folders[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder),
                      title: Text(folderName),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    FavoritesScreen(initialFolder: folderName),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Create new folder…'),
              onTap: () async {
                Navigator.pop(context);
                final name = await _promptNewFolderFromHome(context);
                if (name == null || name.trim().isEmpty) return;
                final trimmed = name.trim();
                if (!svc.folderExists(trimmed)) {
                  await svc.createFolder(trimmed);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FavoritesScreen(initialFolder: trimmed),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: const Text('Manage favourites'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FavoritesScreen(initialFolder: null), // All
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Helper dialog for new folder
Future<String?> _promptNewFolderFromHome(BuildContext context) async {
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

// ---------------------------------------------------------------------
// UI WIDGETS (unchanged from your original design)
// ---------------------------------------------------------------------

class _CategoriesStrip extends StatelessWidget {
  const _CategoriesStrip({required this.onTap});
  final void Function(Category) onTap;

  @override
  Widget build(BuildContext context) {
    final cats = Category.values;
    return SizedBox(
      height: 108,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final c = cats[i];
          return InkWell(
            onTap: () => onTap(c),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surface,
                boxShadow: kElevationToShadow[1],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(c.icon, size: 28),
                  const Spacer(),
                  Text(c.label, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: cats.length,
      ),
    );
  }
}

class _PinnedGrid extends StatelessWidget {
  const _PinnedGrid({
    required this.ids,
    required this.onOpen,
    required this.onRemove,
  });

  final List<String> ids;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onRemove;

  int _colsFor(double w) {
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _colsFor(MediaQuery.of(context).size.width),
        childAspectRatio: 0.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final id = ids[index];
        final thumb = 'https://archive.org/services/img/$id';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(id),
            onLongPress: () async {
              final remove = await showDialog<bool>(
                context: context,
                builder:
                    (ctx) => AlertDialog(
                      title: const Text('Remove pinned collection?'),
                      content: Text(id),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
              );
              if (remove == true) onRemove(id);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Text(
                    id,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      }, childCount: ids.length),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.sfwOnly,
    required this.favouritesOnly,
    required this.downloadedOnly,
    required this.onChanged,
  });

  final bool sfwOnly;
  final bool favouritesOnly;
  final bool downloadedOnly;
  final void Function(bool sfw, bool fav, bool dld) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('SFW'),
            selected: sfwOnly,
            onSelected: (v) => onChanged(v, favouritesOnly, downloadedOnly),
          ),
          FilterChip(
            label: const Text('Favourites'),
            selected: favouritesOnly,
            onSelected: (v) => onChanged(sfwOnly, v, downloadedOnly),
          ),
          FilterChip(
            label: const Text('Downloaded'),
            selected: downloadedOnly,
            onSelected: (v) => onChanged(sfwOnly, favouritesOnly, v),
          ),
        ],
      ),
    );
  }
}

class _PopularGrid extends StatelessWidget {
  const _PopularGrid({required this.onOpen});
  final ValueChanged<String> onOpen;

  static const _items = [
    'internetarchivebooks',
    'opensource',
    'classicpcgames',
    'pulpmagazinearchive',
    'computer_magazines',
    'videogamemagazines',
  ];

  int _colsFor(double w) {
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _colsFor(MediaQuery.of(context).size.width),
        childAspectRatio: 0.8,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      delegate: SliverChildBuilderDelegate((context, i) {
        final id = _items[i];
        final thumb = 'https://archive.org/services/img/$id';
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpen(id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Image.network(
                    thumb,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Text(
                    id,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      }, childCount: _items.length),
    );
  }
}

// ---------------------------------------------------------------------
// SUPPORTING SCREENS (stubs – replace with real ones later)
// ---------------------------------------------------------------------

class ExploreCollectionsScreen extends StatelessWidget {
  final VoidCallback onPinnedChanged;
  const ExploreCollectionsScreen({super.key, required this.onPinnedChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Explore Collections')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}

class ManagePinsScreen extends StatelessWidget {
  final List<String> ids;
  final void Function(int, int) onReorder;
  final ValueChanged<String> onRemove;
  const ManagePinsScreen({
    super.key,
    required this.ids,
    required this.onReorder,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Pinned')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}

class MagazinesHubScreen extends StatelessWidget {
  final ArchiveFilters filters;
  const MagazinesHubScreen({super.key, required this.filters});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Magazines')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}

class ReadingListScreen extends StatelessWidget {
  const ReadingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading Lists')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}

// ---------------------------------------------------------------------
// SEARCH DELEGATE
// ---------------------------------------------------------------------

class _SimpleSearchDelegate extends SearchDelegate<void> {
  _SimpleSearchDelegate(this.filters);
  final ArchiveFilters filters;

  @override
  String? get searchFieldLabel => 'Search Archive (title/subject/creator)…';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      onPressed: query.isEmpty ? null : () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildResults(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const SizedBox.shrink();

    final advQuery =
        '(title:"$q" OR subject:"$q" OR description:"$q" OR creator:"$q")';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => CollectionDetailScreen(
                categoryName: 'Search',
                customQuery: advQuery,
                filters: filters,
              ),
        ),
      );
      close(context, null);
    });

    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
