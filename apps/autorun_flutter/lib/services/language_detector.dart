import 'script_runner.dart';

ScriptLanguage detectLanguage(String source) {
  if (source.trim().isEmpty) return ScriptLanguage.lua;

  if (RegExp(r'function\s+(init|view|update)\s*\(').hasMatch(source)) {
    return ScriptLanguage.lua;
  }
  if (RegExp(r'\n[ \t]*local[ \t]').hasMatch(source)) {
    return ScriptLanguage.lua;
  }
  final endLine = RegExp(r'\bend\s*$');
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('--')) {
      return ScriptLanguage.lua;
    }
    if (endLine.hasMatch(line.trim())) {
      return ScriptLanguage.lua;
    }
  }

  if (source.trimLeft().startsWith('(')) {
    return ScriptLanguage.typescript;
  }
  if (source.contains('=>')) {
    return ScriptLanguage.typescript;
  }
  if (RegExp(r'\bregister\s*\(').hasMatch(source)) {
    return ScriptLanguage.typescript;
  }

  return ScriptLanguage.lua;
}

String scriptLanguageToJson(ScriptLanguage lang) {
  switch (lang) {
    case ScriptLanguage.lua:
      return 'lua';
    case ScriptLanguage.typescript:
      return 'typescript';
  }
}

ScriptLanguage scriptLanguageFromJson(Object? value) {
  if (value is String) {
    switch (value) {
      case 'typescript':
        return ScriptLanguage.typescript;
      case 'lua':
        return ScriptLanguage.lua;
    }
  }
  return ScriptLanguage.lua;
}
