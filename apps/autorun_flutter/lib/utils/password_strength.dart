/// Deterministic, dependency-free password strength scoring.
///
/// Used by the vault-password setup screen's live strength meter (UX-7) and
/// reusable by any future password entry surface (vault unlock, etc.). The
/// scoring is intentionally simple — no zxcvbn, no dictionary, no entropy
/// estimation — and is meant as a *typing-feedback* signal, not a security
/// gate (validation lives in the form's validator).
///
/// Algorithm:
/// - Length: <8 = 0, 8-11 = 1, 12-15 = 2, 16+ = 3
/// - Character classes present (lowercase, uppercase, digit, symbol): 0-4,
///   capped at 3
/// - Total = length + classes, clamped to [0, 4].
library;

const _kMinScore = 0;
const _kMaxScore = 4;

int passwordStrength(String password) {
  final length = password.length;
  final lengthScore = length < 8
      ? 0
      : length < 12
          ? 1
          : length < 16
              ? 2
              : 3;

  var classScore = 0;
  if (RegExp(r'[a-z]').hasMatch(password)) classScore += 1;
  if (RegExp(r'[A-Z]').hasMatch(password)) classScore += 1;
  if (RegExp(r'[0-9]').hasMatch(password)) classScore += 1;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) classScore += 1;
  if (classScore > 3) classScore = 3;

  final total = lengthScore + classScore;
  if (total < _kMinScore) return _kMinScore;
  if (total > _kMaxScore) return _kMaxScore;
  return total;
}

/// Human-readable label for a strength score returned by [passwordStrength].
///
/// Mapping: 0-1 → Weak, 2 → Fair, 3 → Good, 4 → Strong.
String passwordStrengthLabel(int score) {
  if (score <= 1) return 'Weak';
  if (score == 2) return 'Fair';
  if (score == 3) return 'Good';
  return 'Strong';
}
