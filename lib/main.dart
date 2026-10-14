import 'dart:io';

import 'package:flutter/material.dart';

import 'admin_app.dart';
import 'waiter_app.dart';

/// Na računaru se pokreće admin panel, na telefonu unos za konobara.
/// Admin panel na telefonu ne postoji.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await runAdminApp();
  } else {
    await runWaiterApp();
  }
}
