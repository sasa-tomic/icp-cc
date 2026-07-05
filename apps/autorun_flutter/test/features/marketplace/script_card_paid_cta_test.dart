// ignore_for_file: lines_longer_than_80_chars

/// Coverage for the paid-script "Payments Coming Soon" honest CTA — the only
/// user-facing surface that ships this exact dialog today is `ScriptCard`
/// (`lib/widgets/script_card.dart` line 437). The other three prod files that
/// branch on `script.price > 0` (`script_details_dialog.dart`,
/// `script_row_menus.dart`, `marketplace_open_api_service.dart`) carry related
/// paid-path behaviour but none of them surface this dialog, so they are out of
/// scope here and covered by their own / future tests.
///
/// Per HUMAN_EXPECTATIONS §2 ("every shipped thing works as a user"), a shipped
/// widget behaviour with no test is a regression risk. These tests lock the
/// contract so the CTA can't silently regress to:
///   - offering a real Download/Run for a paid script (commerce + auth gap), or
///   - hiding the honest "Payments Coming Soon" copy behind a silent no-op.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/theme/modern_components.dart';
import 'package:icp_autorun/widgets/script_card.dart';

import '_marketplace_test_harness.dart';

/// Single source of truth for the honest CTA copy that `ScriptCard` renders.
///
/// These literals MUST match `lib/widgets/script_card.dart` line-for-line.
/// `ScriptCard` does not currently export them as named constants — extracting
/// `kPaymentsComingSoonTitle` / `kPaymentsComingSoonBody` on the prod side and
/// referencing them symbolically from here would be cleaner (HUMAN_EXPECTATIONS
/// §2: "A single constant lives in ONE place"). Until that refactor lands, the
/// strings are pinned in this one place in the test so a prod copy change trips
/// exactly one assertion target.
const String kPaymentsComingSoonTitle = 'Payments Coming Soon';
const String kPaymentsComingSoonBody =
    'Paid scripts will be available in the next update! '
    "We're working on integrating secure payment processing with ICP tokens.";

/// The CTA label `ScriptCard` renders for a paid script. Same single-source
/// rationale as above — pinned here, referenced once per test.
const String kPaidCtaLabelFor9_99 = '\$9.99';

void main() {
  group('ScriptCard paid-script "Payments Coming Soon" CTA', () {
    /// The real `MarketplaceScript` model — built with the same constructor the
    /// prod screens use (see `scripts_screen.dart` / `script_card_keypair_test`).
    /// `price` is the field that gates the paid branch (`script.price > 0`).
    MarketplaceScript buildScript({required double price}) {
      final now = DateTime.now();
      return MarketplaceScript(
        id: 'script-paid-$price',
        title: 'Pro Script',
        description: 'A script whose price gates the honest-CTA branch.',
        category: 'Utility',
        tags: const ['utility'],
        authorId: 'author-1',
        authorName: 'Pro Author',
        authorPrincipal: 'aaaaa-aa',
        authorPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        uploadSignature: 'c2lnbmF0dXJl',
        price: price,
        currency: 'USD',
        downloads: 42,
        rating: 4.5,
        reviewCount: 10,
        bundle: 'return {}',
        iconUrl: null,
        screenshots: const [],
        canisterIds: const [],
        compatibility: null,
        version: '1.0.0',
        isPublic: true,
        createdAt: now,
        updatedAt: now,
      );
    }

    /// `ScriptCard` uses `Expanded(flex: 2)` in its layout, so it needs bounded
    /// height — same wrap the existing `script_card_keypair_test.dart` uses.
    Future<void> pumpCard(
      WidgetTester tester, {
      required MarketplaceScript script,
      required VoidCallback onDownload,
    }) async {
      await pumpMarketplaceWidget(
        tester,
        Center(
          child: SizedBox(
            // `ScriptCard` lays out icon (flex 2) + content (flex 4) in a
            // Column of `Expanded`s, so it needs bounded height. 320 was enough
            // for the keypair-badge tests (no onDownload button); once the CTA
            // row is rendered the content Column needs a little more room, so
            // give it 420 to avoid an "overflowed by N px" layout error that
            // would mask the actual contract assertions.
            width: 320,
            height: 420,
            child: ScriptCard(
              script: script,
              onTap: () {},
              onDownload: onDownload,
            ),
          ),
        ),
      );
    }

    testWidgets(
        'POSITIVE: paid script (price > 0) CTA opens the "Payments Coming Soon" '
        'dialog with the honest copy and does NOT trigger a real download',
        (tester) async {
      final script = buildScript(price: 9.99);
      var downloadInvocations = 0;

      await pumpCard(
        tester,
        script: script,
        onDownload: () => downloadInvocations++,
      );

      // The CTA renders the price, not the "Download FREE" affordance — that
      // alone is what tells the user this is a paid tier. There are two
      // "$9.99" Text nodes in the card (the price chip up top, and the CTA
      // button at the bottom); we deliberately target the ModernButton one,
      // since that's the tappable affordance the user actually reaches.
      final paidCta =
          find.widgetWithText(ModernButton, kPaidCtaLabelFor9_99);
      expect(paidCta, findsOneWidget,
          reason: 'Paid-script CTA must render the price as its label');
      expect(find.text('Download FREE'), findsNothing,
          reason: 'A paid script must NOT offer the free-download affordance');

      await tester.tap(paidCta);
      await tester.pumpAndSettle();

      // Honest CTA: the dialog surfaces the title + body copy verbatim.
      expect(find.text(kPaymentsComingSoonTitle), findsOneWidget);
      expect(find.text(kPaymentsComingSoonBody), findsOneWidget);

      // The honest CTA must NOT have side-effected a real download — commerce
      // + auth on paid scripts is gated server-side too (see
      // `marketplace_open_api_service.dart` line 349: throws on price > 0).
      expect(downloadInvocations, 0,
          reason: 'Tapping the paid CTA must not invoke onDownload at all');
    });

    testWidgets(
        'POSITIVE: the "Payments Coming Soon" dialog dismisses via its OK '
        'action (the user is not trapped on the honest interstitial)',
        (tester) async {
      final script = buildScript(price: 9.99);

      await pumpCard(
        tester,
        script: script,
        onDownload: () {},
      );

      await tester.tap(find.widgetWithText(ModernButton, kPaidCtaLabelFor9_99));
      await tester.pumpAndSettle();

      expect(find.text(kPaymentsComingSoonTitle), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text(kPaymentsComingSoonTitle), findsNothing,
          reason: 'OK must dismiss the honest-CTA interstitial');
    });

    testWidgets(
        'NEGATIVE: a FREE script (price == 0) does NOT show "Payments Coming '
        'Soon" — it offers the real Download path',
        (tester) async {
      final script = buildScript(price: 0);
      var downloadInvocations = 0;

      await pumpCard(
        tester,
        script: script,
        onDownload: () => downloadInvocations++,
      );

      // The free affordance is present; the paid-CTA price label is not.
      final freeCta = find.text('Download FREE');
      expect(freeCta, findsOneWidget);
      expect(find.text(kPaidCtaLabelFor9_99), findsNothing);

      await tester.tap(freeCta);
      await tester.pumpAndSettle();

      // Real download path: onDownload fired, no honest interstitial shown.
      expect(downloadInvocations, 1,
          reason: 'The free-script CTA must invoke the real onDownload');
      expect(find.text(kPaymentsComingSoonTitle), findsNothing);
      expect(find.text(kPaymentsComingSoonBody), findsNothing);
    });

    testWidgets(
        'NEGATIVE: a FREE script with default-constructed price (omitted → 0.0) '
        'also takes the real Download path, never the paid CTA',
        (tester) async {
      // Mirrors how most call sites construct a marketplace script — they rely
      // on the `price = 0.0` default rather than passing it explicitly. Guards
      // against a future change that flips the default to non-zero.
      final now = DateTime.now();
      final script = MarketplaceScript(
        id: 'script-default-price',
        title: 'Default-Priced Script',
        description: 'price field defaulted by the model constructor',
        category: 'Utility',
        bundle: 'return {}',
        createdAt: now,
        updatedAt: now,
      );

      var downloadInvocations = 0;
      await pumpCard(
        tester,
        script: script,
        onDownload: () => downloadInvocations++,
      );

      final freeCta = find.text('Download FREE');
      expect(freeCta, findsOneWidget);
      await tester.tap(freeCta);
      await tester.pumpAndSettle();

      expect(downloadInvocations, 1);
      expect(find.text(kPaymentsComingSoonTitle), findsNothing);
    });
  });
}
