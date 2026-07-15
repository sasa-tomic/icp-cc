import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/script_list_item.dart';
import 'package:icp_autorun/screens/script_context_menu.dart';

import '_scripts_test_harness.dart';

/// W7-18: `ScriptContextMenuSheet` had zero test references despite driving 7
/// conditional action callbacks + section routing (local vs marketplace). A
/// regression that dropped Delete, showed Delete for a non-owned script, or
/// wired the wrong callback would ship unnoticed.
///
/// These tests pin the I/O boundary only: the sheet is pumped inside a real
/// `showModalBottomSheet` (so `Navigator.pop` on tap closes the sheet, exactly
/// as in production), and each callback is a counter-recording spy. They assert
/// (a) which actions render for each script source, (b) that a null callback
/// hides its action, (c) that tapping each action fires its callback exactly
/// once and closes the sheet, and (d) the download-state variants.
void main() {
  group('ScriptContextMenuSheet rendering', () {
    testWidgets('local script shows local actions and hides marketplace ones',
        (tester) async {
      await _pumpMenu(
        tester,
        ScriptContextMenuSheet(
          item: ScriptListItem.fromLocal(aLocalScript(title: 'Local One')),
          onRun: () {},
          onEdit: () {},
          onDuplicate: () {},
          onDelete: () {},
          onPublish: () {},
        ),
      );

      // Local section actions.
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Share to Marketplace'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Marketplace-only actions must never appear for a local script.
      expect(find.text('View Details'), findsNothing);
      expect(find.text('Download'), findsNothing);
      expect(find.text('Already Downloaded'), findsNothing);

      // Source badge.
      expect(find.text('Local'), findsOneWidget);
      expect(find.text('Marketplace'), findsNothing);
    });

    testWidgets(
        'marketplace script shows marketplace actions and hides local ones',
        (tester) async {
      await _pumpMenu(
        tester,
        ScriptContextMenuSheet(
          item: ScriptListItem.fromMarketplace(aMarketplaceScript()),
          onViewDetails: () {},
          onDownload: () {},
        ),
      );

      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);

      // Local-only actions must never appear for a marketplace listing.
      expect(find.text('Run'), findsNothing);
      expect(find.text('Edit'), findsNothing);
      expect(find.text('Duplicate'), findsNothing);
      expect(find.text('Share to Marketplace'), findsNothing);
      expect(find.text('Delete'), findsNothing);

      // Source badge.
      expect(find.text('Marketplace'), findsOneWidget);
      expect(find.text('Local'), findsNothing);
    });

    testWidgets('a null callback hides its action (onDelete absent)',
        (tester) async {
      await _pumpMenu(
        tester,
        ScriptContextMenuSheet(
          item: ScriptListItem.fromLocal(aLocalScript()),
          onRun: () {},
          // onDelete deliberately null → Delete must not render.
        ),
      );

      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Delete'), findsNothing,
          reason: 'a null onDelete must hide the destructive action');
    });

    testWidgets('already-downloaded marketplace script shows confirmation, '
        'hides the Download button', (tester) async {
      await _pumpMenu(
        tester,
        ScriptContextMenuSheet(
          item: ScriptListItem.fromMarketplace(aMarketplaceScript()),
          isDownloaded: true,
          onViewDetails: () {},
          onDownload: () {},
        ),
      );

      expect(find.text('Already Downloaded'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('downloading state relabels the action and disables the tap',
        (tester) async {
      var downloadCalls = 0;
      await _pumpMenu(
        tester,
        ScriptContextMenuSheet(
          item: ScriptListItem.fromMarketplace(aMarketplaceScript()),
          isDownloading: true,
          onViewDetails: () {},
          onDownload: () => downloadCalls++,
        ),
      );

      expect(find.text('Downloading...'), findsOneWidget);
      expect(find.text('Download'), findsNothing);

      // Tapping a disabled action must not fire the callback nor close the
      // sheet.
      await tester.tap(find.text('Downloading...'));
      await tester.pumpAndSettle();

      expect(downloadCalls, 0);
      expect(find.byType(ScriptContextMenuSheet), findsOneWidget);
    });
  });

  group('ScriptContextMenuSheet tap wiring', () {
    // Each tap pops the sheet, so each action is exercised in isolation with a
    // fresh sheet + a spy that records every callback.
    for (final case_ in _localTapCases()) {
      testWidgets('tapping "${case_.label}" fires its callback once and closes '
          'the sheet', (tester) async {
        final spy = _ActionSpy();
        await _pumpMenu(tester, spy.localSheet());

        await tester.tap(find.text(case_.label));
        await tester.pumpAndSettle();

        expect(case_.countOf(spy), 1, reason: '${case_.label} callback fired');
        // The other callbacks must stay untouched.
        for (final other in _localTapCases()) {
          if (other.label != case_.label) {
            expect(other.countOf(spy), 0,
                reason: '${other.label} should not fire');
          }
        }
        expect(find.byType(ScriptContextMenuSheet), findsNothing,
            reason: 'tapping an action must close the sheet');
      });
    }

    for (final case_ in _marketplaceTapCases()) {
      testWidgets('tapping "${case_.label}" on a marketplace script fires its '
          'callback once', (tester) async {
        final spy = _ActionSpy();
        await _pumpMenu(tester, spy.marketplaceSheet());

        await tester.tap(find.text(case_.label));
        await tester.pumpAndSettle();

        expect(case_.countOf(spy), 1);
        expect(find.byType(ScriptContextMenuSheet), findsNothing);
      });
    }
  });
}

/// Pumps [sheet] inside a real `showModalBottomSheet` (the production entry
/// point) so the sheet's `Navigator.pop`-on-tap behaviour is exercised
/// faithfully. The surface is sized larger than the default 800×600 so the
/// sheet host's default `isScrollControlled:false` height cap and the action
/// row widths have headroom — these tests assert action ROUTING and CALLBACK
/// wiring, not pixel layout (separate layout-polish findings are noted in the
/// W7-18 report).
Future<void> _pumpMenu(WidgetTester tester, ScriptContextMenuSheet sheet) async {
  final originalSize = tester.view.physicalSize;
  final originalDpr = tester.view.devicePixelRatio;
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.physicalSize = originalSize;
    tester.view.devicePixelRatio = originalDpr;
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                builder: (_) => sheet,
              ),
              child: const Text('Show Menu'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Show Menu'));
  await tester.pumpAndSettle();
}

/// Records how many times each action callback fires. The callbacks ARE the
/// I/O boundary the sheet drives, so this is the correct seam to mock.
class _ActionSpy {
  int run = 0;
  int edit = 0;
  int duplicate = 0;
  int delete = 0;
  int publish = 0;
  int viewDetails = 0;
  int download = 0;

  ScriptContextMenuSheet localSheet() => ScriptContextMenuSheet(
        item: ScriptListItem.fromLocal(aLocalScript()),
        onRun: () => run++,
        onEdit: () => edit++,
        onDuplicate: () => duplicate++,
        onDelete: () => delete++,
        onPublish: () => publish++,
      );

  ScriptContextMenuSheet marketplaceSheet() => ScriptContextMenuSheet(
        item: ScriptListItem.fromMarketplace(aMarketplaceScript()),
        onViewDetails: () => viewDetails++,
        onDownload: () => download++,
      );
}

class _TapCase {
  const _TapCase(this.label, this.countOf);
  final String label;
  final int Function(_ActionSpy) countOf;
}

List<_TapCase> _localTapCases() => const [
      _TapCase('Run', _runCount),
      _TapCase('Edit', _editCount),
      _TapCase('Duplicate', _duplicateCount),
      _TapCase('Share to Marketplace', _publishCount),
      _TapCase('Delete', _deleteCount),
    ];

List<_TapCase> _marketplaceTapCases() => const [
      _TapCase('View Details', _viewDetailsCount),
      _TapCase('Download', _downloadCount),
    ];

int _runCount(_ActionSpy s) => s.run;
int _editCount(_ActionSpy s) => s.edit;
int _duplicateCount(_ActionSpy s) => s.duplicate;
int _deleteCount(_ActionSpy s) => s.delete;
int _publishCount(_ActionSpy s) => s.publish;
int _viewDetailsCount(_ActionSpy s) => s.viewDetails;
int _downloadCount(_ActionSpy s) => s.download;
