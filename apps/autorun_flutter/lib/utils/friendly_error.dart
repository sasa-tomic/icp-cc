import 'error_categories.dart';

/// Returns a short, user-facing message for [error], suitable for inline
/// contexts (SnackBar, dialog body, in-form error text).
///
/// Classifies by exception TYPE (never by grepping the message string —
/// see `lib/widgets/canister_client_sheet.dart` TD-9) via the existing
/// `categorizeError` + `ErrorInfo.userMessage` infrastructure, then prepends
/// [context] (e.g. 'Download failed') when supplied so the call-site phrase
/// is preserved:
///
///   friendlyErrorMessage(e, context: 'Download failed')
///   // => 'Download failed: Could not connect to the server'
///
/// Sites that need a richer UX (icon, retry, help) should use the
/// `ErrorDisplay` widget directly with `errorObject:` — this helper is for
/// the SnackBar / inline-text cases where a widget does not fit.
String friendlyErrorMessage(Object error, {String? context}) {
  final body = getErrorInfo(categorizeError(error)).userMessage;
  return context == null || context.isEmpty ? body : '$context: $body';
}

/// Returns a cleaned-up verbatim form of [error] suitable for an optional
/// "Show details" expander, or `null` when there is nothing useful beyond
/// the friendly message.
///
/// Strips the noisy `Exception: ` prefix that Dart's `Exception.toString()`
/// inserts; masks opaque dumps (`Instance of 'X'`, raw HTML server pages,
/// empty strings) that would only confuse users without aiding support.
String? friendlyErrorDetail(Object error) {
  var raw = error.toString();
  raw = raw.replaceAll(RegExp(r'^Exception:\s*'), '');
  if (raw.isEmpty) return null;
  if (RegExp(r"^Instance of(?:\s|'$|'$)").hasMatch(raw)) return null;
  if (RegExp(r'<(?:html|!doctype)', caseSensitive: false).hasMatch(raw)) {
    return null;
  }
  return raw;
}
