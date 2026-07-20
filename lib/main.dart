import 'package:flutter/material.dart';

import 'app/app.dart';

export 'app/app.dart' show PilgrimApp;
export 'core/shared/widgets/searchable_dropdown.dart'
    show SearchableDropdown, SearchableSelect;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PilgrimApp());
}
