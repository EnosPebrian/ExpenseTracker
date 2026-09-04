import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pilgrim_tracker/features/health/domain/health_check_models.dart';
import 'package:pilgrim_tracker/features/health/domain/health_check_service.dart';
import 'package:pilgrim_tracker/features/health/presentation/controllers/health_check_controller.dart';
import 'package:pilgrim_tracker/features/health/presentation/screens/health_check_screen.dart';

void main() {
  testWidgets(
    'Health Check runs, expands sections, copies summary, and reruns',
    (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      final controller = HealthCheckController(_FakeHealthService());
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        controller.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HealthCheckScreen(controller: controller)),
        ),
      );
      expect(find.text('Run Health Check'), findsOneWidget);

      await tester.tap(find.text('Run Health Check'));
      await tester.pumpAndSettle();

      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Run Again'), findsOneWidget);
      await tester.tap(find.text('Database'));
      await tester.pumpAndSettle();
      expect(find.text('SQLite schema'), findsOneWidget);

      final copyButton = find.widgetWithText(OutlinedButton, 'Copy summary');
      await tester.ensureVisible(copyButton);
      await tester.pumpAndSettle();
      await tester.tap(copyButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Privacy-safe diagnostic summary copied.'),
        findsOneWidget,
      );
      expect(copiedText, contains('Pilgrim Tracker Health Check'));

      await tester.ensureVisible(find.text('Run Again'));
      await tester.tap(find.text('Run Again'));
      await tester.pumpAndSettle();
      expect(controller.report, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Health Check lays out on a Windows-wide surface', (
    tester,
  ) async {
    final controller = HealthCheckController(_FakeHealthService());
    await controller.run();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async {
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthCheckScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Health Check'), findsOneWidget);
    expect(find.text('Healthy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Health Check renders attention and critical states', (
    tester,
  ) async {
    final warningController = HealthCheckController(
      _FakeHealthService(status: HealthCheckItemStatus.warning),
    );
    await warningController.run();
    addTearDown(warningController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthCheckScreen(controller: warningController)),
      ),
    );
    expect(find.text('Attention needed'), findsWidgets);

    final errorController = HealthCheckController(
      _FakeHealthService(status: HealthCheckItemStatus.error),
    );
    await errorController.run();
    addTearDown(errorController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HealthCheckScreen(controller: errorController)),
      ),
    );
    expect(find.text('Critical'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _FakeHealthService extends HealthCheckService {
  _FakeHealthService({this.status = HealthCheckItemStatus.healthy})
    : super(dataSource: _UnusedSource());

  final HealthCheckItemStatus status;

  @override
  Future<HealthCheckReport> run() async => HealthCheckReport(
    generatedAt: DateTime(2026, 9, 1, 8, 15),
    sections: [
      HealthCheckSection(
        id: 'database',
        title: 'Database',
        checks: [
          HealthCheckItem(
            code: 'database.schema_version',
            title: 'SQLite schema',
            status: status,
            summary: 'SQLite schema: v25',
          ),
        ],
      ),
      HealthCheckSection(
        id: 'sync',
        title: 'Sync',
        checks: const [
          HealthCheckItem(
            code: 'sync.mode',
            title: 'Sync mode',
            status: HealthCheckItemStatus.info,
            summary: 'Sync mode: Local only.',
          ),
        ],
      ),
    ],
  );
}

class _UnusedSource implements HealthCheckDataSource {
  @override
  Future<HealthCheckSnapshot> load() => throw UnimplementedError();
}
