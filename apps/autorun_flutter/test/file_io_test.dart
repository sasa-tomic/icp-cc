import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/file_io.dart';
import 'package:icp_autorun/theme/app_design_system.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_io_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<File> createBlockingFifo(String name) async {
    final path = '${tempDir.path}/$name';
    final result = await Process.run('mkfifo', [path]);
    if (result.exitCode != 0) {
      throw StateError(
        'mkfifo exited ${result.exitCode}: ${result.stderr}. '
        'This test requires a POSIX environment with mkfifo.',
      );
    }
    return File(path);
  }

  Future<void> releaseBlockedReader(File fifo) async {
    final sink = fifo.openWrite(mode: FileMode.write);
    await sink.flush();
    await sink.close();
  }

  test('readJson raises TimeoutException when read exceeds the bound', () async {
    final fifo = await createBlockingFifo('blocked_read.json');

    final stopwatch = Stopwatch()..start();
    await expectLater(
      readJson(fifo, bound: const Duration(milliseconds: 120)),
      throwsA(isA<TimeoutException>()),
    );
    stopwatch.stop();
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));

    await releaseBlockedReader(fifo);
  });

  test('readJson returns file contents on the happy path', () async {
    final file = File('${tempDir.path}/ok.json');
    await file.writeAsString('{"a":1}');
    expect(await readJson(file), '{"a":1}');
  });

  test('writeJson round-trips through readJson', () async {
    final file = File('${tempDir.path}/rw.json');
    await writeJson(file, '{"b":2}');
    expect(await readJson(file), '{"b":2}');
  });

  test('ioOperation token is the single source of truth at 5 seconds', () {
    expect(AppDurations.ioOperation, const Duration(seconds: 5));
  });
}
