import 'dart:io';

/// The text of a file, read again only when its modified time or size
/// changes. So a full page load does not read the root view and the
/// Vite manifest from disk each time, and an edit in dev still shows.
// ponytail: one stat per call. Cache forever if the stat ever shows up
// in a profile.
class FileCache {
  static final Map<String, _Entry> _entries = <String, _Entry>{};

  /// The text of the file at [path]. Throws like [File.readAsString]
  /// when there is no file.
  static Future<String> read(String path) async {
    File file = File(path);
    FileStat stat = await file.stat();
    _Entry? entry = _entries[path];
    if (entry != null &&
        entry.modified == stat.modified &&
        entry.size == stat.size) {
      return entry.text;
    }
    String text = await file.readAsString();
    _entries[path] = _Entry(stat.modified, stat.size, text);
    return text;
  }
}

class _Entry {
  _Entry(this.modified, this.size, this.text);

  final DateTime modified;
  final int size;
  final String text;
}
