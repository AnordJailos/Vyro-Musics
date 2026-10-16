import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

abstract class RecentSearchStore {
  Future<List<String>> load();
  Future<void> save(List<String> searches);
}

class MemoryRecentSearchStore implements RecentSearchStore {
  List<String> saved = [];

  @override
  Future<List<String>> load() async => List.of(saved);

  @override
  Future<void> save(List<String> searches) async => saved = List.of(searches);
}

class FileRecentSearchStore implements RecentSearchStore {
  FileRecentSearchStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}recent_searches.json');
  }

  @override
  Future<List<String>> load() async {
    final f = await _file();
    if (!await f.exists()) return [];
    try {
      return [for (final s in (jsonDecode(await f.readAsString()) as List)) '$s'];
    } catch (_) {
      return []; // a damaged file is ignored rather than stopping the app
    }
  }

  @override
  Future<void> save(List<String> searches) async {
    final f = await _file();
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(jsonEncode(searches));
    await temp.rename(f.path); // write then rename, so a crash never leaves half a file
  }
}

/// What the person searched for lately, newest first, kept on the device.
class RecentSearches extends ChangeNotifier {
  RecentSearches({required this.store, this.max = 10});

  final RecentSearchStore store;
  final int max;
  List<String> _items = const [];

  List<String> get items => _items;

  Future<void> load() async {
    _items = (await store.load()).take(max).toList();
    notifyListeners();
  }

  /// Remembers a search. One letter is not worth keeping, and searching the same thing again moves it to the front.
  Future<void> add(String query) async {
    final q = query.trim();
    if (q.length < 2) return;
    _items = [q, for (final s in _items) if (s.toLowerCase() != q.toLowerCase()) s].take(max).toList();
    notifyListeners();
    await store.save(_items);
  }

  Future<void> remove(String query) async {
    _items = [for (final s in _items) if (s != query) s];
    notifyListeners();
    await store.save(_items);
  }

  Future<void> clear() async {
    _items = const [];
    notifyListeners();
    await store.save(_items);
  }
}

class RecentSearchesScope extends InheritedNotifier<RecentSearches> {
  const RecentSearchesScope({super.key, required RecentSearches controller, required super.child}) : super(notifier: controller);

  static RecentSearches? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<RecentSearchesScope>()?.notifier;
}
