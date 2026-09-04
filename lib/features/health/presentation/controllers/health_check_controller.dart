import 'package:flutter/foundation.dart';

import '../../domain/health_check_models.dart';
import '../../domain/health_check_service.dart';

class HealthCheckController extends ChangeNotifier {
  HealthCheckController(this.service);

  final HealthCheckService service;
  HealthCheckReport? report;
  bool running = false;

  Future<void> run() async {
    if (running) return;
    running = true;
    notifyListeners();
    try {
      report = await service.run();
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
