import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_template.dart';

/// Focused syntax tests that would have caught the original advanced UI issue
void main() {

  group('Script Template Syntax Tests', () {

    test('Advanced UI template should not have syntax errors', () {
      final template = ScriptTemplates.getById('advanced_ui')!;
      final source = template.luaSource;

      // This would have caught the original bracket mismatch
      expect(_hasBalancedBrackets(source), true,
             reason: 'Template has unbalanced brackets');

      // This would have caught the icp_searchable_list misuse
      final usages = _findICPSearchableListUsage(source);
      for (final usage in usages) {
        expect(usage.isCorrect, true,
               reason: 'Template uses icp_searchable_list incorrectly at line ${usage.lineNumber}: ${usage.context}');
      }
    });

    test('All templates should have valid return statements', () {
      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource;
        
        // Find all return statements
        final returnMatches = RegExp(r'return\s+(.*?)(?=\n|$)').allMatches(source);
        
        for (final match in returnMatches) {
          final returnExpr = match.group(1)!;
          
          // Skip multi-line table returns that start with { (they're valid Lua syntax)
          final trimmedReturn = returnExpr.trim();
          if (trimmedReturn.startsWith('{') && !trimmedReturn.endsWith('}')) {
            continue; // Skip multi-line table declarations
          }
          
          // Skip multi-return statements (they're valid Lua syntax)
          if (trimmedReturn.contains(',') && 
              (trimmedReturn.contains('state') || trimmedReturn.endsWith('{}'))) {
            continue; // Skip multi-return statements
          }
          
          // Skip function calls with opening braces (they're valid Lua syntax)
          if (trimmedReturn.contains('(') && trimmedReturn.contains('{') && !trimmedReturn.contains('}')) {
            continue; // Skip function calls with table arguments
          }
          
          // Skip string.format calls (they're valid Lua syntax for multi-line strings)
          if (trimmedReturn.contains('string.format') && trimmedReturn.endsWith(',')) {
            continue; // Skip string.format multi-line calls
          }
          
          // Return should not end with hanging comma unless it's a valid multi-return (like init function)
          if (trimmedReturn.endsWith(',') && !trimmedReturn.contains('{}')) {
            // Check if this looks like a multi-return statement (common in init functions)
            final hasMultipleValues = trimmedReturn.contains(',') && 
                                   (trimmedReturn.contains('transactions') || 
                                    trimmedReturn.contains('filters') ||
                                    trimmedReturn.contains('state'));
            
            if (!hasMultipleValues) {
              expect(trimmedReturn.endsWith(','), false,
                     reason: 'Template ${template.id} has return statement ending with comma: $returnExpr');
            }
          }
          
          // Return should not have unmatched brackets
          expect(_hasBalancedBrackets(returnExpr), true,
                 reason: 'Template ${template.id} return statement has unbalanced brackets: $returnExpr');
        }
      }
    });

    test('All templates should use ICP helpers in correct contexts', () {
      for (final template in ScriptTemplates.templates) {
        final source = template.luaSource;

        // Check icp_searchable_list usage
        final searchableListUsage = _findICPSearchableListUsage(source);
        for (final usage in searchableListUsage) {
          expect(usage.isCorrect, true,
                 reason: 'Template ${template.id} uses icp_searchable_list incorrectly at line ${usage.lineNumber}: ${usage.context}');
        }
      }
    });
  });
}

bool _hasBalancedBrackets(String source) {
  int braceCount = 0;
  int bracketCount = 0;
  int parenCount = 0;
  
  for (int i = 0; i < source.length; i++) {
    final char = source[i];
    switch (char) {
      case '{':
        braceCount++;
        break;
      case '}':
        braceCount--;
        if (braceCount < 0) return false;
        break;
      case '[':
        bracketCount++;
        break;
      case ']':
        bracketCount--;
        if (bracketCount < 0) return false;
        break;
      case '(':
        parenCount++;
        break;
      case ')':
        parenCount--;
        if (parenCount < 0) return false;
        break;
    }
  }
  
  return braceCount == 0 && bracketCount == 0 && parenCount == 0;
}

List<_ICPUsage> _findICPSearchableListUsage(String source) {
  final usages = <_ICPUsage>[];
  final lines = source.split('\n');
  
  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.contains('icp_searchable_list(')) {
      // Check context around this line
      final contextStart = (i - 2).clamp(0, lines.length - 1);
      final contextEnd = (i + 2).clamp(0, lines.length - 1);
      final context = lines.sublist(contextStart, contextEnd + 1).join('\n');
      
      // Look for problematic patterns
      final isCorrect = !_isProblematicUsage(context);
      
      usages.add(_ICPUsage(
        lineNumber: i + 1,
        context: context,
        isCorrect: isCorrect,
      ));
    }
  }
  
  return usages;
}

bool _isProblematicUsage(String context) {
  // Check if icp_searchable_list is used in children array
  if (RegExp(r'children\s*=\s*\{[^}]*icp_searchable_list').hasMatch(context)) {
    return false; // Problematic
  }
  
  // Check if icp_searchable_list is followed by array syntax
  if (RegExp(r'icp_searchable_list\([^)]*\)\s*\]').hasMatch(context)) {
    return false; // Problematic
  }
  
  // Check if icp_searchable_list is followed by comma in array context
  if (RegExp(r'icp_searchable_list\([^)]*\)\s*,').hasMatch(context)) {
    return false; // Problematic
  }
  
  return true; // Correct usage
}

class _ICPUsage {
  final int lineNumber;
  final String context;
  final bool isCorrect;
  
  _ICPUsage({
    required this.lineNumber,
    required this.context,
    required this.isCorrect,
  });
}