import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pull-to-refresh functionality', () {
    testWidgets('RefreshIndicator triggers callback on pull', (tester) async {
      int refreshCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () async {
                refreshCount++;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 5,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      expect(refreshCount, 0);

      await tester.fling(
        find.byType(ListView),
        const Offset(0, 500),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshCount, 1);
    });

    testWidgets('RefreshIndicator shows loading indicator during refresh',
        (tester) async {
      final completer = Future<void>.delayed(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () => completer,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 5,
                itemBuilder: (context, index) =>
                    ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      await tester.fling(
        find.byType(ListView),
        const Offset(0, 500),
        1000,
      );
      await tester.pump();

      expect(find.byType(RefreshProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('RefreshIndicator requires AlwaysScrollableScrollPhysics',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefreshIndicator(
              onRefresh: () async {},
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 0,
                itemBuilder: (context, index) => const SizedBox(),
              ),
            ),
          ),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}
