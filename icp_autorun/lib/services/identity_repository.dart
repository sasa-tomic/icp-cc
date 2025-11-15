import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/identity_record.dart';

class IdentityRepository {
  IdentityRepository({Directory? overrideDirectory})
    : _overrideDirectory = overrideDirectory;

  final Directory? _overrideDirectory;
  bool _initialized = false;
  File? _storeFile;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      throw UnsupportedError('IdentityRepository does not support web yet.');
    }

    Directory directory;
    if (_overrideDirectory != null) {
      directory = _overrideDirectory!;
    } else {
      try {
        directory = await getApplicationSupportDirectory();
      } catch (_) {
        // In test or restricted environments where platform channels are unavailable,
        // fall back to a temporary directory to avoid hanging initialization.
        directory = await Directory.systemTemp.createTemp('icp_autorun_test_');
      }
    }
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final File file = File('${directory.path}/identities.json');
    if (!await file.exists()) {
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'identities': <Map<String, dynamic>>[],
        }),
      );
    }

    _storeFile = file;
    _initialized = true;
  }

  Future<List<IdentityRecord>> loadIdentities() async {
    await _ensureInitialized();
    final File file = _storeFile!;
    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <IdentityRecord>[];
      }
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid identity store format.');
      }
      final List<dynamic> identities =
          decoded['identities'] as List<dynamic>? ?? <dynamic>[];
      return identities
          .map(
            (dynamic item) =>
                IdentityRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on FormatException {
      // If parsing fails we back up the corrupted file and start fresh.
      final String backupPath = '${file.path}.bak';
      await file.copy(backupPath);
      await file.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'identities': <Map<String, dynamic>>[],
        }),
      );
      return <IdentityRecord>[];
    }
  }

  Future<void> persistIdentities(List<IdentityRecord> identities) async {
    await _ensureInitialized();
    final File file = _storeFile!;
    final Map<String, dynamic> payload = <String, dynamic>{
      'version': 1,
      'identities': identities
          .map((IdentityRecord record) => record.toJson())
          .toList(),
    };
    await file.writeAsString(jsonEncode(payload));
  }
}
