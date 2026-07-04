/// Relative-date formatter shared by [ScriptDetailsDialog] and its extracted
/// reviews / versions tab widgets.
///
/// Promoted verbatim from the dialog's file-private `_formatDate` during the
/// TD-11 split so both tab files can reuse it without duplicating logic or
/// introducing a cross-file import cycle. Pure mechanical move — behaviour
/// unchanged (only the leading `_` was dropped, as Dart requires for
/// cross-file access, matching the TD-10 convention).
String formatDate(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inDays > 365) {
    return '${(difference.inDays / 365).floor()} year${(difference.inDays / 365).floor() == 1 ? '' : 's'} ago';
  } else if (difference.inDays > 30) {
    return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() == 1 ? '' : 's'} ago';
  } else if (difference.inDays > 0) {
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
  } else {
    return 'Just now';
  }
}
