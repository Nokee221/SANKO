import 'package:flutter/material.dart';

import 'admin_app.dart';

/// Ulaz samo za admin panel, bez lokalne baze telefona; ovako se pokreće i u pregledaču:
/// flutter run -d chrome -t lib/main_admin.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runAdminApp();
}
