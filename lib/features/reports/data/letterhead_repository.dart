import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/models/letterhead_template.dart';

class LetterheadsRepository {
  static const _folderName = 'letterheads';
  static const _indexFile = 'letterheads_index.json';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _index() async {
    final dir = await _dir();
    return File('${dir.path}/$_indexFile');
  }

  Future<List<String>> _readIndexIds() async {
    final f = await _index();
    if (!await f.exists()) return [];

    final raw = await f.readAsString();
    if (raw.trim().isEmpty) return [];

    final decoded = jsonDecode(raw);
    final ids = (decoded as List).map((e) => e.toString()).toList();
    return ids;
  }

  Future<void> _writeIndexIds(List<String> ids) async {
    final f = await _index();
    await f.writeAsString(jsonEncode(ids));
  }

  Future<File> _fileFor(String letterheadId) async {
    final dir = await _dir();
    return File('${dir.path}/$letterheadId.json');
  }

  /// List all letterheads (most recent first is optional; we keep by index order)
  Future<List<LetterheadTemplate>> listLetterheads() async {
    final ids = await _readIndexIds();
    final items = <LetterheadTemplate>[];

    for (final id in ids) {
      try {
        final t = await loadLetterhead(id);
        items.add(t);
      } catch (_) {
        // ignore broken entry
      }
    }
    return items;
  }

  Future<LetterheadTemplate> loadLetterhead(String letterheadId) async {
    final f = await _fileFor(letterheadId);
    if (!await f.exists()) {
      throw Exception('Letterhead not found');
    }

    final raw = await f.readAsString();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return LetterheadTemplate.fromJson(map);
  }

  Future<void> saveLetterhead(LetterheadTemplate t) async {
    // write template file
    final f = await _fileFor(t.letterheadId);
    await f.writeAsString(jsonEncode(t.toJson()));

    // update index
    final ids = await _readIndexIds();
    if (!ids.contains(t.letterheadId)) {
      ids.insert(0, t.letterheadId); // newest first feels nice
      await _writeIndexIds(ids);
    }
  }
Future<List<LetterheadTemplate>> loadAll() async {
  final dir = await _dir();

  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'));

  final result = <LetterheadTemplate>[];

  for (final f in files) {
    try {
      final text = await f.readAsString();
      final decoded = jsonDecode(text);

      // Case 1: file contains ONE template object: { ... }
      if (decoded is Map) {
        result.add(
          LetterheadTemplate.fromJson(
            Map<String, dynamic>.from(decoded),
          ),
        );
        continue;
      }

      // Case 2: file contains MANY templates: [ {...}, {...} ]
      if (decoded is List) {
        result.addAll(
          decoded
              .whereType<Map>()
              .map((e) => LetterheadTemplate.fromJson(
                    Map<String, dynamic>.from(e),
                  )),
        );
        continue;
      }
    } catch (_) {
      // Ignore corrupt/old files so app doesn't crash
      continue;
    }
  }

  return result;
}



  Future<void> deleteLetterhead(String letterheadId) async {
    final f = await _fileFor(letterheadId);
    if (await f.exists()) {
      await f.delete();
    }

    final ids = await _readIndexIds();
    ids.remove(letterheadId);
    await _writeIndexIds(ids);
  }

  /// Optional helper: copy a picked logo into the letterheads folder
  /// so the path stays stable (recommended).
  Future<String> importLogoFile({
    required String sourcePath,
    required String letterheadId,
  }) async {
    final dir = await _dir();
    final src = File(sourcePath);
    if (!await src.exists()) throw Exception('Logo file not found');

    // keep extension if present
    final ext = _safeExt(sourcePath);
    final dest = File('${dir.path}/logo_$letterheadId$ext');

    await src.copy(dest.path);
    return dest.path;
  }

  String _safeExt(String path) {
    final i = path.lastIndexOf('.');
    if (i == -1) return '';
    final ext = path.substring(i);
    // keep simple whitelist
    if (ext.length > 6) return '';
    return ext;
  }
}
