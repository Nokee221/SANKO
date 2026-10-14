import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/app.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/ui/admin/obracun_page.dart';
import 'package:sanko/ui/admin/scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

void main() {
  late Database db;
  late Repository repo;
  late String kola;
  late String kafa;
  late Shift second;

  /// Dvije zaključene smjene danas: kola 77 → 88 → 80, kafa 1000 → 1100 → 1200.
  Future<void> setUp(WidgetTester tester) async {
    await tester.runAsync(() async {
      db = await openTestDb(isolate: false);
      var now = DateTime.now().copyWith(hour: 8);
      repo = Repository(db, now: () => now);
      await repo.addWorker(name: 'Kenan', pin: '1111');
      await repo.addItem(
        name: 'KAFA',
        kind: ItemKind.counter,
        price: 250,
        initialQty: 1000,
      );
      await repo.addItem(
        name: 'KOLA',
        kind: ItemKind.stock,
        price: 350,
        initialQty: 77,
      );
      final ids = {for (final i in await repo.items()) i.name: i.id};
      kola = ids['KOLA']!;
      kafa = ids['KAFA']!;
      final kenan = (await repo.workerByPin('1111'))!;
      Future<Shift> shift(int coffee, int cola) async {
        final s = await repo.startShift(kenan.id);
        await repo.setClosingQty(s.id, kafa, coffee);
        await repo.setClosingQty(s.id, kola, cola);
        await repo.closeShift(s.id);
        return repo.shiftById(s.id);
      }

      await shift(1100, 88);
      now = now.add(const Duration(hours: 6));
      second = await shift(1200, 80);
    });
    addTearDown(() => db.close());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AdminScope(
        data: repo,
        child: const SankoMaterialApp(home: Scaffold(body: ObracunPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<int> opening(WidgetTester tester, Shift s, String item) async {
    final o = (await tester.runAsync(() => repo.obracunForShift(s.id)))!;
    return o.lines.firstWhere((l) => l.itemId == item).opening;
  }

  testWidgets(
    'gazda ispravlja ostatak i ulaz, a sljedeća smjena preuzima ostatak',
    (tester) async {
      await setUp(tester);
      expect(
        find.text('Ispravi smjenu'),
        findsNothing,
        reason: 'samo za jednu smjenu',
      );

      await tester.tap(find.textContaining('Smjena 1, Kenan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ispravi smjenu'));
      await tester.pumpAndSettle();

      // Zaboravljen ulaz od 24 i ponovo prebrojano 80 umjesto 88.
      await tester.enterText(find.byKey(ValueKey('primljeno-$kola')), '24');
      await tester.enterText(find.byKey(ValueKey('ostatak-$kola')), '80');
      await tester.pump();
      expect(find.text('21'), findsOneWidget, reason: 'utrošeno: 77 + 24 - 80');
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Razlog ispravke (npr. greška u brojanju)',
        ),
        'Zaboravljen ulaz',
      );
      await tester.tap(find.text('Sačuvaj ispravku'));
      await tester.pumpAndSettle();

      expect(find.text('Ispravke'), findsOneWidget);
      expect(find.text('ostatak 88 → 80'), findsOneWidget);
      expect(find.text('primljeno 0 → 24'), findsOneWidget);
      expect(find.text('Zaboravljen ulaz'), findsNWidgets(2));
      expect(find.textContaining('(ispravljeno)'), findsOneWidget);
      expect(await opening(tester, second, kola), 80);
    },
  );

  testWidgets('brojač se ne može ispraviti ispod prethodnog stanja', (
    tester,
  ) async {
    await setUp(tester);
    await tester.tap(find.textContaining('Smjena 1, Kenan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ispravi smjenu'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ValueKey('ostatak-$kafa')), '900');
    await tester.tap(find.text('Sačuvaj ispravku'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ne može biti manji'), findsOneWidget);
    await tester.tap(find.text('U redu'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sačuvaj ispravku'),
      findsOneWidget,
      reason: 'prozor ostaje otvoren',
    );
    expect(await opening(tester, second, kafa), 1100);
  });
}
