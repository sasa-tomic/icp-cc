import 'dart:io';

import '../theme/app_design_system.dart';

Future<String> readJson(File file, {Duration bound = AppDurations.ioOperation}) =>
    file.readAsString().timeout(bound);

Future<void> writeJson(
  File file,
  String contents, {
  Duration bound = AppDurations.ioOperation,
}) =>
    file.writeAsString(contents).timeout(bound);
