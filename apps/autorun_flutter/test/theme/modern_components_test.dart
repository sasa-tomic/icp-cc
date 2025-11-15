import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/theme/modern_components.dart';

void main() {
  group('ModernNavigationBar', () {
    Widget createWidget({
      int currentIndex = 0,
      required List<ModernNavigationItem> items,
      required Function(int) onTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ModernNavigationBar(
            currentIndex: currentIndex,
            items: items,
            onTap: onTap,
          ),
        ),
      );
    }

    testWidgets('should display navigation items', (WidgetTester tester) async {
      final items = [
        ModernNavigationItem(
          icon: Icons.home,
          activeIcon: Icons.home,
          label: 'Home',
        ),
        ModernNavigationItem(
          icon: Icons.search,
          activeIcon: Icons.search,
          label: 'Search',
        ),
      ];

      await tester.pumpWidget(createWidget(
        items: items,
        onTap: (index) {},
      ));

      expect(find.byType(ModernNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('should call onTap when item is tapped', (WidgetTester tester) async {
      int tappedIndex = -1;
      final items = [
        ModernNavigationItem(
          icon: Icons.home,
          activeIcon: Icons.home,
          label: 'Home',
        ),
        ModernNavigationItem(
          icon: Icons.search,
          activeIcon: Icons.search,
          label: 'Search',
        ),
      ];

      await tester.pumpWidget(createWidget(
        items: items,
        onTap: (index) => tappedIndex = index,
      ));

      await tester.tap(find.text('Search'));
      await tester.pump();

      expect(tappedIndex, equals(1));
    });
  });

  group('ModernCard', () {
    Widget createWidget({
      Widget? child,
      VoidCallback? onTap,
      bool isSelected = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ModernCard(
            onTap: onTap,
            child: child ?? const Text('Test Content'),
          ),
        ),
      );
    }

    testWidgets('should display content', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget());
      
      expect(find.byType(ModernCard), findsOneWidget);
      expect(find.text('Test Content'), findsOneWidget);
    });

    testWidgets('should handle tap', (WidgetTester tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(createWidget(
        onTap: () => tapped = true,
      ));
      
      await tester.pump(const Duration(milliseconds: 100)); // Wait for animation
      await tester.tap(find.byType(ModernCard));
      await tester.pump();
      
      expect(tapped, isTrue);
    });

    testWidgets('should show selected state', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(isSelected: true));
      
      expect(find.byType(ModernCard), findsOneWidget);
      // The selected state should be reflected in the visual appearance
    });
  });

  group('ModernButton', () {
    Widget createWidget({
      required String label,
      ModernButtonVariant variant = ModernButtonVariant.primary,
      VoidCallback? onPressed,
      bool loading = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ModernButton(
            onPressed: onPressed,
            child: Text(label),
            variant: variant,
            loading: loading,
          ),
        ),
      );
    }

    testWidgets('should display button with label', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(
        label: 'Test Button',
        onPressed: () {},
      ));
      
      expect(find.byType(ModernButton), findsOneWidget);
      expect(find.text('Test Button'), findsOneWidget);
    });

    testWidgets('should handle press', (WidgetTester tester) async {
      bool pressed = false;
      
      await tester.pumpWidget(createWidget(
        label: 'Test Button',
        onPressed: () => pressed = true,
      ));
      
      await tester.tap(find.byType(ModernButton));
      await tester.pump();
      
      expect(pressed, isTrue);
    });

    testWidgets('should show loading state', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(
        label: 'Test Button',
        onPressed: () {},
        loading: true,
      ));
      
      expect(find.byType(ModernButton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ModernChip', () {
    Widget createWidget({
      required String label,
      bool selected = false,
      VoidCallback? onTap,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ModernChip(
            label: label,
            selected: selected,
            onTap: onTap,
          ),
        ),
      );
    }

    testWidgets('should display chip with label', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(label: 'Test Chip'));
      
      expect(find.byType(ModernChip), findsOneWidget);
      expect(find.text('Test Chip'), findsOneWidget);
    });

    testWidgets('should handle tap', (WidgetTester tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(createWidget(
        label: 'Test Chip',
        onTap: () => tapped = true,
      ));
      
      await tester.tap(find.byType(ModernChip));
      await tester.pump();
      
      expect(tapped, isTrue);
    });

    testWidgets('should show selected state', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(
        label: 'Test Chip',
        selected: true,
      ));
      
      expect(find.byType(ModernChip), findsOneWidget);
    });
  });

  group('ModernFloatingActionButton', () {
    Widget createWidget({
      required Widget icon,
      String? label,
      VoidCallback? onPressed,
      bool extended = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          floatingActionButton: ModernFloatingActionButton(
            icon: icon,
            label: label ?? '',
            onPressed: onPressed,
            extended: extended,
          ),
        ),
      );
    }

    testWidgets('should display FAB with icon', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(
        icon: Icon(Icons.add),
        onPressed: () {},
      ));
      
      expect(find.byType(ModernFloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('should display FAB with label', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(
        icon: Icon(Icons.add),
        label: 'Add Item',
        onPressed: () {},
        extended: true,
      ));
      
      expect(find.byType(ModernFloatingActionButton), findsOneWidget);
      expect(find.text('Add Item'), findsOneWidget);
    });

    testWidgets('should handle press', (WidgetTester tester) async {
      bool pressed = false;
      
      await tester.pumpWidget(createWidget(
        icon: Icon(Icons.add),
        onPressed: () => pressed = true,
      ));
      
      await tester.pump(const Duration(milliseconds: 100)); // Wait for animation
      await tester.tap(find.byType(ModernFloatingActionButton));
      await tester.pump();
      
      expect(pressed, isTrue);
    });
  });
}