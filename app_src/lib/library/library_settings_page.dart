import 'package:flutter/material.dart';

import 'library_controller.dart';

/// Which folders the library looks in, which are left out, and how short a song can be and still be kept.
class LibrarySettingsPage extends StatelessWidget {
  const LibrarySettingsPage({super.key, required this.library});

  final LibraryController library;

  static const _lengths = {0: 'Keep everything', 10: '10 seconds', 30: '30 seconds', 60: '1 minute', 120: '2 minutes'};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final lengths = {..._lengths.keys, library.minSeconds}.toList()..sort();
        return Scaffold(
          appBar: AppBar(title: const Text('Library settings')),
          body: ListView(
            children: [
              const _Header('Music folders'),
              if (library.roots.isEmpty)
                const ListTile(title: Text("Your device's usual music folders"), subtitle: Text('Add a folder to choose where to look instead.')),
              for (final r in library.roots)
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(r, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(tooltip: 'Remove folder $r', icon: const Icon(Icons.close_rounded), onPressed: () => library.removeFolder(r)),
                ),
              ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('Add a folder'), onTap: library.addFolder),
              const _Header('Left out'),
              if (library.excludedFolders.isEmpty) const ListTile(title: Text('No folders are left out.')),
              for (final e in library.excludedFolders)
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: TextButton(onPressed: () => library.removeExcludedFolder(e), child: const Text('Include again')),
                ),
              ListTile(leading: const Icon(Icons.block_rounded), title: const Text('Leave out a folder'), subtitle: const Text('For example voice notes or ringtones.'), onTap: library.addExcludedFolder),
              const _Header('Short clips'),
              ListTile(
                title: const Text('Ignore songs shorter than'),
                trailing: DropdownButton<int>(
                  value: library.minSeconds,
                  items: [for (final s in lengths) DropdownMenuItem(value: s, child: Text(_lengths[s] ?? '$s seconds'))],
                  onChanged: (v) {
                    if (v != null) library.setMinSeconds(v);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(text, style: Theme.of(context).textTheme.titleSmall));
}
