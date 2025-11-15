import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/script_record.dart';

class ScriptRepository {
  ScriptRepository({Directory? overrideDirectory}) : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  bool _initialized = false;
  File? _storeFile;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    if (kIsWeb) {
      throw UnsupportedError('ScriptRepository does not support web yet.');
    }

    Directory directory;
    final Directory? override = _overrideDirectory;
    if (override != null) {
      directory = override;
    } else {
      try {
        directory = await getApplicationSupportDirectory();
      } catch (_) {
        directory = await Directory.systemTemp.createTemp('icp_scripts_test_');
      }
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final File file = File('${directory.path}/scripts.json');
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'version': 1,
        'scripts': <Map<String, dynamic>>[],
      }));
    }

    _storeFile = file;
    _initialized = true;
  }

  Future<List<ScriptRecord>> loadScripts() async {
    await _ensureInitialized();
    final File file = _storeFile!;
    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) return <ScriptRecord>[];
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid scripts store format.');
      }
      final List<dynamic> arr = decoded['scripts'] as List<dynamic>? ?? <dynamic>[];
      return arr
          .map((dynamic item) => ScriptRecord.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    } on FormatException {
      final String backupPath = '${file.path}.bak';
      await file.copy(backupPath);
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'version': 1,
        'scripts': <Map<String, dynamic>>[],
      }));
      return <ScriptRecord>[];
    }
  }

  Future<void> persistScripts(List<ScriptRecord> scripts) async {
    await _ensureInitialized();
    final File file = _storeFile!;
    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 1,
      'scripts': scripts.map((ScriptRecord s) => s.toJson()).toList(),
    };
    await file.writeAsString(jsonEncode(payload));
  }
}
