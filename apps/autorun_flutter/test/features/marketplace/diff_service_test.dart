import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/services/diff_service.dart';

void main() {
  group('DiffService', () {
    group('compute', () {
      test('returns empty result for identical strings', () {
        const code = 'local x = 1\nprint(x)';
        final result = DiffService.compute(code, code);

        expect(result.hasChanges, isFalse);
      });

      test('marks all lines as added for new file (empty old)', () {
        const oldCode = '';
        const newCode = 'local x = 1\nprint(x)';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, equals(2));
        expect(result.deletions, equals(0));
        expect(result.lines.every((l) => l.isAddition), isTrue);
      });

      test('marks all lines as removed for deleted file (empty new)', () {
        const oldCode = 'local x = 1\nprint(x)';
        const newCode = '';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, equals(0));
        expect(result.deletions, equals(2));
        expect(result.lines.every((l) => l.isRemoval), isTrue);
      });

      test('detects single line addition', () {
        const oldCode = 'local x = 1';
        const newCode = 'local x = 1\nlocal y = 2';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, equals(1));
        expect(result.deletions, equals(0));
        final addedLine = result.lines.firstWhere((l) => l.isAddition);
        expect(addedLine.content, equals('local y = 2'));
      });

      test('detects single line removal', () {
        const oldCode = 'local x = 1\nlocal y = 2';
        const newCode = 'local x = 1';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, equals(0));
        expect(result.deletions, equals(1));
        final removedLine = result.lines.firstWhere((l) => l.isRemoval);
        expect(removedLine.content, equals('local y = 2'));
      });

      test('detects line modification (removal + addition)', () {
        const oldCode = 'local x = 1';
        const newCode = 'local x = 2';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, equals(1));
        expect(result.deletions, equals(1));
      });

      test('preserves unchanged lines with line numbers', () {
        const oldCode = 'line1\nline2\nline3';
        const newCode = 'line1\nline2\nline3';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.lines.length, equals(3));
        for (var i = 0; i < result.lines.length; i++) {
          expect(result.lines[i].oldLineNumber, equals(i + 1));
          expect(result.lines[i].newLineNumber, equals(i + 1));
          expect(result.lines[i].content, equals('line${i + 1}'));
        }
      });

      test('handles multi-line changes correctly', () {
        const oldCode = '''
function greet()
  print("Hello")
end
''';
        const newCode = '''
function greet(name)
  print("Hello, " .. name)
end
''';

        final result = DiffService.compute(oldCode, newCode);

        expect(result.additions, greaterThanOrEqualTo(2));
        expect(result.deletions, greaterThanOrEqualTo(2));
      });
    });

    group('DiffLine', () {
      test('isAddition returns true for added lines', () {
        const line = DiffLine(
          newLineNumber: 1,
          content: 'test',
          type: DiffLineType.added,
        );
        expect(line.isAddition, isTrue);
        expect(line.isRemoval, isFalse);
      });

      test('isRemoval returns true for removed lines', () {
        const line = DiffLine(
          oldLineNumber: 1,
          content: 'test',
          type: DiffLineType.removed,
        );
        expect(line.isRemoval, isTrue);
        expect(line.isAddition, isFalse);
      });
    });

    group('DiffResult', () {
      test('hasChanges returns true when additions exist', () {
        final result = DiffResult(
          lines: const [
            DiffLine(
                newLineNumber: 1, content: 'test', type: DiffLineType.added),
          ],
          additions: 1,
          deletions: 0,
        );
        expect(result.hasChanges, isTrue);
      });

      test('hasChanges returns true when deletions exist', () {
        final result = DiffResult(
          lines: const [
            DiffLine(
                oldLineNumber: 1, content: 'test', type: DiffLineType.removed),
          ],
          additions: 0,
          deletions: 1,
        );
        expect(result.hasChanges, isTrue);
      });

      test('hasChanges returns false when no changes', () {
        const result = DiffResult(lines: [], additions: 0, deletions: 0);
        expect(result.hasChanges, isFalse);
      });
    });
  });
}
