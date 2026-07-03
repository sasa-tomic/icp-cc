import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_scripts_test_harness.dart';

/// Active filter-chips behaviour. The previous version of this file was almost
/// entirely `expect(true, isTrue)` "code-verification" placeholders (zero
/// signal — they could never fail). Only the single behavioural assertion that
/// the chips section is absent until a filter is active is retained.
void main() {
  testWidgets('no filter chips shown when no filters are active', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpScriptsScreen(tester);

    // 'active_filter_chips' is the Key the search bar tags its chips row with
    // (lib/widgets/scripts_search_bar.dart). With every filter at its default,
    // the row must not render.
    expect(find.byKey(const Key('active_filter_chips')), findsNothing);

    await tester.binding.setSurfaceSize(null);
  });
}
