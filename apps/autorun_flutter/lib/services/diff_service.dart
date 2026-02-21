enum DiffLineType {
  added,
  removed,
  unchanged,
  header,
}

class DiffLine {
  final int? oldLineNumber;
  final int? newLineNumber;
  final String content;
  final DiffLineType type;

  const DiffLine({
    this.oldLineNumber,
    this.newLineNumber,
    required this.content,
    required this.type,
  });

  bool get isAddition => type == DiffLineType.added;
  bool get isRemoval => type == DiffLineType.removed;
  bool get isHeader => type == DiffLineType.header;
}

class DiffResult {
  final List<DiffLine> lines;
  final int additions;
  final int deletions;

  const DiffResult({
    required this.lines,
    required this.additions,
    required this.deletions,
  });

  bool get isEmpty => lines.isEmpty;
  bool get hasChanges => additions > 0 || deletions > 0;
}

class DiffService {
  static DiffResult compute(String oldText, String newText) {
    if (oldText.isEmpty && newText.isEmpty) {
      return const DiffResult(lines: [], additions: 0, deletions: 0);
    }

    if (oldText.isEmpty) {
      final newLines = newText.split('\n');
      return DiffResult(
        lines: newLines
            .asMap()
            .entries
            .map((e) => DiffLine(
                  oldLineNumber: null,
                  newLineNumber: e.key + 1,
                  content: e.value,
                  type: DiffLineType.added,
                ))
            .toList(),
        additions: newLines.length,
        deletions: 0,
      );
    }

    if (newText.isEmpty) {
      final oldLines = oldText.split('\n');
      return DiffResult(
        lines: oldLines
            .asMap()
            .entries
            .map((e) => DiffLine(
                  oldLineNumber: e.key + 1,
                  newLineNumber: null,
                  content: e.value,
                  type: DiffLineType.removed,
                ))
            .toList(),
        additions: 0,
        deletions: oldLines.length,
      );
    }

    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final result = <DiffLine>[];
    int additions = 0;
    int deletions = 0;

    final lcs = _longestCommonSubsequence(oldLines, newLines);

    int oldIdx = 0;
    int newIdx = 0;
    int lcsIdx = 0;

    while (oldIdx < oldLines.length || newIdx < newLines.length) {
      if (lcsIdx < lcs.length &&
          oldIdx < oldLines.length &&
          newIdx < newLines.length &&
          oldLines[oldIdx] == lcs[lcsIdx] &&
          newLines[newIdx] == lcs[lcsIdx]) {
        result.add(DiffLine(
          oldLineNumber: oldIdx + 1,
          newLineNumber: newIdx + 1,
          content: oldLines[oldIdx],
          type: DiffLineType.unchanged,
        ));
        oldIdx++;
        newIdx++;
        lcsIdx++;
      } else if (oldIdx < oldLines.length &&
          (lcsIdx >= lcs.length || oldLines[oldIdx] != lcs[lcsIdx])) {
        result.add(DiffLine(
          oldLineNumber: oldIdx + 1,
          newLineNumber: null,
          content: oldLines[oldIdx],
          type: DiffLineType.removed,
        ));
        deletions++;
        oldIdx++;
      } else if (newIdx < newLines.length) {
        result.add(DiffLine(
          oldLineNumber: null,
          newLineNumber: newIdx + 1,
          content: newLines[newIdx],
          type: DiffLineType.added,
        ));
        additions++;
        newIdx++;
      }
    }

    return DiffResult(
      lines: _insertChunkHeaders(result),
      additions: additions,
      deletions: deletions,
    );
  }

  static List<String> _longestCommonSubsequence(
      List<String> a, List<String> b) {
    final m = a.length;
    final n = b.length;

    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1];
        }
      }
    }

    final lcs = <String>[];
    int i = m, j = n;
    while (i > 0 && j > 0) {
      if (a[i - 1] == b[j - 1]) {
        lcs.insert(0, a[i - 1]);
        i--;
        j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }

    return lcs;
  }

  static List<DiffLine> _insertChunkHeaders(List<DiffLine> lines) {
    if (lines.isEmpty) return lines;

    final result = <DiffLine>[];
    bool inChange = false;
    int unchangedCount = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isChange = line.type != DiffLineType.unchanged;

      if (!inChange && isChange && unchangedCount > 0) {
        result.add(DiffLine(
          content: '...',
          type: DiffLineType.header,
        ));
      }

      if (isChange) {
        unchangedCount = 0;
        inChange = true;
      } else {
        unchangedCount++;
        if (unchangedCount > 6) {
          inChange = false;
          continue;
        }
      }

      result.add(line);
    }

    return result;
  }
}
