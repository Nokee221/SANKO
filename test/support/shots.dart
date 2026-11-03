import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Snimci ekrana se prave samo sa SANKO_SHOTS=1 i --update-goldens.
final shotsEnabled = Platform.environment['SANKO_SHOTS'] == '1';

/// Učitava Manrope i ikone, da snimci izgledaju kao na telefonu.
Future<void> loadShotFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final manrope = FontLoader('Manrope');
  for (final w in [400, 500, 600, 700, 800]) {
    manrope.addFont(
      File(
        'assets/fonts/Manrope-$w.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await manrope.load();
  await (FontLoader('MaterialIcons')..addFont(
        File(
          '$dir/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      ))
      .load();
}

Future<void> shot(String name) async {
  if (!shotsEnabled) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/$name.png'),
  );
}
