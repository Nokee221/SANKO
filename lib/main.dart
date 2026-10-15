import 'dart:io';

import 'package:flutter/material.dart';

import 'admin_app.dart';
import 'phone_app.dart';

/// Na računaru se pokreće admin panel; na telefonu aplikacija za konobara ili gazdu.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await runAdminApp();
  } else {
    await runPhoneApp();
  }
}
