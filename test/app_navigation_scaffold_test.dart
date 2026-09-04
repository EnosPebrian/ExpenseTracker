import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/app/presentation/widgets/app_navigation_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMobileScaffold(
    WidgetTester tester, {
    required ValueChanged<int> onSelect,
    VoidCallback? onQuickAdd,
    int selected = 0,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AppNavigationScaffold(
          selected: selected,
          onSelect: onSelect,
          onQuickAdd: onQuickAdd ?? () {},
          child: const Center(child: Text('Current page')),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('More opens all additional mobile destinations', (tester) async {
    await pumpMobileScaffold(tester, onSelect: (_) {});

    expect(find.text('Categories'), findsNothing);
    expect(find.text('Asset Conversion'), findsNothing);
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Tithe'), findsNothing);
    expect(find.text('Reports'), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Asset Conversion'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Tithe'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Data & Sync'), findsOneWidget);
  });

  testWidgets('Selecting Reports from More returns destination index 9', (
    tester,
  ) async {
    int? selectedIndex;

    await pumpMobileScaffold(
      tester,
      onSelect: (index) {
        selectedIndex = index;
      },
    );

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 9);
    expect(find.text('Reports'), findsNothing);
  });

  testWidgets('Mobile floating action button triggers Quick Add', (
    tester,
  ) async {
    var quickAddOpened = false;

    await pumpMobileScaffold(
      tester,
      onSelect: (_) {},
      onQuickAdd: () {
        quickAddOpened = true;
      },
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(quickAddOpened, isTrue);
  });

  testWidgets('Additional destination keeps More selected on mobile', (
    tester,
  ) async {
    await pumpMobileScaffold(tester, selected: 7, onSelect: (_) {});

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );

    expect(navigationBar.selectedIndex, 3);
  });

  testWidgets(
    'desktop navigation scrolls without overflowing at short height',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: AppNavigationScaffold(
            selected: 6,
            onSelect: (_) {},
            onQuickAdd: () {},
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('side-nav-scroll-view')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('All synced'), findsOneWidget);
    },
  );
}
