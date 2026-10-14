import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/app.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/ui/admin/obracun_page.dart';
import 'package:sanko/ui/admin/prosjek_page.dart';
import 'package:sanko/ui/admin/scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

void main() {
  late Database db;
  late Repository repo;
  final today = DateTime.now();
  var now = today;

  /// Smjene od prije [days.length] dana do danas; breskva se troši koliko piše.
  Future<void> history(WidgetTester tester, List<int> sold) async {
    await tester.runAsync(() async {
      db = await openTestDb(isolate: false);
      repo = Repository(db, now: () => now);
      await repo.addWorker(name: 'Kenan', pin: '1111');
      await repo.addItem(
        name: 'BRESKVA',
        kind: ItemKind.stock,
        price: 350,
        initialQty: 500,
      );
      await repo.addItem(
        name: 'KOLA',
        kind: ItemKind.stock,
        price: 350,
        initialQty: 500,
      );
      final kenan = (await repo.workerByPin('1111'))!;
      for (final (i, n) in sold.indexed) {
        now = DateTime(
          today.year,
          today.month,
          today.day,
          12,
        ).subtract(Duration(days: sold.length - 1 - i));
        final shift = await repo.startShift(kenan.id);
        for (final l in (await repo.obracunForShift(shift.id)).lines) {
          await repo.setClosingQty(
            shift.id,
            l.itemId,
            l.total - (l.name == 'BRESKVA' ? n : 2),
          );
        }
        await repo.closeShift(shift.id);
      }
    });
    addTearDown(() => db.close());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
  }

  Widget app(Widget page) => AdminScope(
    data: repo,
    child: SankoMaterialApp(home: Scaffold(body: page)),
  );

  testWidgets('obračun označava artikal čija potrošnja odskače od prosjeka', (
    tester,
  ) async {
    await history(tester, [5, 4, 6, 5, 20]);
    await tester.pumpWidget(app(const ObracunPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Označeni artikli'), findsOneWidget);
    expect(find.byTooltip('Inače oko 5,0 po danu'), findsOneWidget);
  });

  testWidgets('bez odstupanja nema oznake', (tester) async {
    await history(tester, [5, 4, 6, 5, 6]);
    await tester.pumpWidget(app(const ObracunPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Označeni artikli'), findsNothing);
  });

  testWidgets('stranica Prosjek prikazuje prosjeke i moguće greške', (
    tester,
  ) async {
    await history(tester, [5, 4, 6, 5, 20]);
    await tester.pumpWidget(app(const ProsjekPage()));
    await tester.pumpAndSettle();

    expect(find.text('Moguće greške u brojanju'), findsOneWidget);
    expect(find.text('utrošeno 20, inače oko 5,0'), findsOneWidget);
    // Breskva: 40 komada u 5 dana, jedna smjena dnevno, pa je isto po danu i po smjeni.
    expect(find.text('8,0'), findsNWidgets(2));
    expect(find.text('2,0'), findsWidgets);

    await tester.tap(find.text('Zadnjih 7 dana'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('5 dana rada, 5 zaključenih smjena'),
      findsOneWidget,
    );
  });

  testWidgets(
    'niska zaliha se vidi na današnjem obračunu i na stranici Prosjek',
    (tester) async {
      // Breskva počinje sa 500 i troši se 5 dnevno; kola po 2. Gazda prebroji samo 7 breskvi.
      await history(tester, [5, 5, 5, 5, 5]);
      await tester.runAsync(() async {
        final last = (await repo.shiftsOn(DateTime.now())).single;
        final breskva = (await repo.items()).firstWhere(
          (i) => i.name == 'BRESKVA',
        );
        final o = await repo.obracunForShift(last.id);
        final closing = o.lines
            .firstWhere((l) => l.itemId == breskva.id)
            .closing!;
        await repo.correctShift(last.id, [
          ItemCorrection(itemId: breskva.id, closing: 7),
        ]);
        expect(closing, 475);
      });

      await tester.pumpWidget(app(const ObracunPage()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Niska zaliha: BRESKVA (zaliha 7'),
        findsOneWidget,
      );

      await tester.pumpWidget(app(const ProsjekPage()));
      await tester.pumpAndSettle();
      expect(find.text('Niska zaliha'), findsOneWidget);
      expect(find.textContaining('zaliha 7, dovoljno za oko'), findsOneWidget);
    },
  );
}
