/// D33: every recorded map is kept as `maps/<name>-<timestamp>.json`, and
/// `maps/active.txt` names the one Navigate and the floor map use. A new
/// recording never overwrites an older map.
///
/// `maps/latest.json` stays a copy of the active map, so tools that pull it
/// keep working. An install from before D33 has only latest.json and no
/// active.txt: it is migrated once as the first saved map.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/contracts.dart';
import '../core/map_json.dart';

/// One saved map file. [id] is the file name; it never changes, even on rename.
class SavedMap {
  const SavedMap({
    required this.id,
    required this.map,
    required this.savedAt,
    required this.path,
  });

  final String id;
  final MapGraph map;
  final DateTime savedAt;
  final String path;

  String get name => map.name;

  /// Named places (start and marked places), not junctions.
  int get placeCount =>
      map.places.where((p) => p.kind != PlaceKind.junction).length;
}

class MapLibrary {
  MapLibrary({Future<Directory> Function()? documentsDirectory})
    : _documents = documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documents;

  static const activeFile = 'active.txt';
  static const latestFile = 'latest.json';
  static final _stamp = RegExp(r'-(\d{8})-(\d{6})(?:-\d+)?\.json$');

  Future<Directory> _dir() async {
    final docs = await _documents();
    final dir = Directory('${docs.path}${Platform.pathSeparator}maps');
    await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  /// A file-name-safe version of [name]: lowercase letters, digits and dashes.
  static String slug(String name) {
    final s = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final cut = s.length > 40
        ? s.substring(0, 40).replaceAll(RegExp(r'-+$'), '')
        : s;
    return cut.isEmpty ? 'map' : cut;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static DateTime? _savedAt(String id) {
    final m = _stamp.firstMatch(id);
    if (m == null) return null;
    final d = m.group(1)!, t = m.group(2)!;
    return DateTime(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
      int.parse(t.substring(0, 2)),
      int.parse(t.substring(2, 4)),
      int.parse(t.substring(4, 6)),
    );
  }

  static bool _isMapId(String id) => id != latestFile && _stamp.hasMatch(id);

  /// Moves a pre-D33 latest.json into the library once (when there is no
  /// active.txt yet). latest.json itself is left in place.
  Future<void> _migrate(Directory dir) async {
    final active = _file(dir, activeFile);
    if (await active.exists()) return;
    final latest = _file(dir, latestFile);
    if (await latest.exists()) {
      try {
        final content = await latest.readAsString();
        final map = decodeMap(content);
        final id = await _freeId(dir, map.name, await latest.lastModified());
        await _file(dir, id).writeAsString(content, flush: true);
        await active.writeAsString(id, flush: true);
        return;
      } catch (_) {
        // An unreadable latest.json is left alone and not migrated.
      }
    }
    await active.writeAsString('', flush: true);
  }

  Future<String> _freeId(Directory dir, String name, DateTime at) async {
    final base = '${slug(name)}-${stamp(at)}';
    var id = '$base.json';
    for (var n = 2; await _file(dir, id).exists(); n++) {
      id = '$base-$n.json';
    }
    return id;
  }

  /// Every readable saved map, newest first. A file that doesn't parse is
  /// skipped, not deleted.
  Future<List<SavedMap>> list() async {
    final dir = await _dir();
    await _migrate(dir);
    final maps = <SavedMap>[];
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final id = entry.uri.pathSegments.last;
      if (!_isMapId(id)) continue;
      try {
        maps.add(
          SavedMap(
            id: id,
            map: decodeMap(await entry.readAsString()),
            savedAt: _savedAt(id)!,
            path: entry.path,
          ),
        );
      } catch (_) {}
    }
    maps.sort((a, b) {
      final byTime = b.savedAt.compareTo(a.savedAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return maps;
  }

  /// The active map's ID, or null when none is set.
  Future<String?> activeId() async {
    final dir = await _dir();
    await _migrate(dir);
    final id = (await _file(dir, activeFile).readAsString()).trim();
    return id.isEmpty ? null : id;
  }

  /// The active map, or null (no maps, or the pointer names a missing file).
  Future<SavedMap?> loadActive() async {
    final id = await activeId();
    if (id == null) return null;
    for (final saved in await list()) {
      if (saved.id == id) return saved;
    }
    return null;
  }

  /// Saves [map] as a new file and makes it active. Returns its path.
  Future<SavedMap> save(MapGraph map, {DateTime? now}) async {
    final dir = await _dir();
    await _migrate(dir);
    final id = await _freeId(dir, map.name, now ?? DateTime.now());
    final file = _file(dir, id);
    await file.writeAsString(encodeMap(map), flush: true);
    final saved = SavedMap(
      id: id,
      map: map,
      savedAt: _savedAt(id)!,
      path: file.path,
    );
    await _setActive(dir, saved);
    return saved;
  }

  Future<void> setActive(String id) async {
    final dir = await _dir();
    await _migrate(dir);
    final file = _file(dir, id);
    if (!_isMapId(id) || !await file.exists()) {
      throw ArgumentError('No saved map $id');
    }
    final content = await file.readAsString();
    await _setActive(
      dir,
      SavedMap(
        id: id,
        map: decodeMap(content),
        savedAt: _savedAt(id)!,
        path: file.path,
      ),
    );
  }

  Future<void> _setActive(Directory dir, SavedMap saved) async {
    await _file(dir, activeFile).writeAsString(saved.id, flush: true);
    await _file(
      dir,
      latestFile,
    ).writeAsString(encodeMap(saved.map), flush: true);
  }

  /// Changes the map's display name (its `name` field); the file keeps its ID.
  Future<void> rename(String id, String newName) async {
    final name = newName.trim();
    if (name.isEmpty) throw ArgumentError('A map needs a name');
    final dir = await _dir();
    final file = _file(dir, id);
    if (!_isMapId(id) || !await file.exists()) {
      throw ArgumentError('No saved map $id');
    }
    final old = decodeMap(await file.readAsString());
    final renamed = MapGraph(
      version: old.version,
      name: name,
      start: old.start,
      places: old.places,
      corridors: old.corridors,
    );
    await file.writeAsString(encodeMap(renamed), flush: true);
    if (await activeId() == id) {
      await _file(
        dir,
        latestFile,
      ).writeAsString(encodeMap(renamed), flush: true);
    }
  }

  /// Deletes one saved map. If it was active, the newest remaining map becomes
  /// active; with none left, latest.json is removed too and Navigate falls
  /// back to the demo map.
  Future<void> delete(String id) async {
    final dir = await _dir();
    if (!_isMapId(id)) throw ArgumentError('No saved map $id');
    final wasActive = await activeId() == id;
    final file = _file(dir, id);
    if (await file.exists()) await file.delete();
    if (!wasActive) return;
    final rest = await list();
    if (rest.isNotEmpty) {
      await _setActive(dir, rest.first);
    } else {
      await _file(dir, activeFile).writeAsString('', flush: true);
      final latest = _file(dir, latestFile);
      if (await latest.exists()) await latest.delete();
    }
  }
}
