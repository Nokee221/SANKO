import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/orders.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/sync/waiter_sync.dart';
import 'package:sanko/ui/format.dart';
import 'package:sanko/waiter_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

void main() {
  late Database serverDb;
  late Database phoneDb;
  late Repository server;
  late Repository phone;
  late FakeBackend backend;
  late WaiterSync sync;
  late List<Order> orders;

  Future<void> setUpPhone(WidgetTester tester) async {
    await tester.runAsync(() async {
      serverDb = await openTestDb(isolate: false);
      server = Repository(serverDb);
      await server.addWorker(name: 'Amra', pin: '1111');
      await server.addWorker(name: 'Bakir', pin: '2222', role: WorkerRole.sank);
      await server.seedDemoItems();
      orders = [];
      phoneDb = await openTestDb(isolate: false);
      phone = Repository(phoneDb);
      backend = FakeBackend(server, serverDb, orders: orders);
      sync = WaiterSync(phone, backend, autoSync: false);
      await sync.init();
      await sync.setVenueCode(testVenueCode);
    });
    addTearDown(() async {
      await phoneDb.close();
      await serverDb.close();
    });
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester, String pin) async {
    await tester.pumpWidget(WaiterApp(repo: phone, sync: sync));
    await tester.pumpAndSettle();
    for (final d in pin.split('')) {
      await tapText(tester, d);
    }
  }

  /// Narudžba kao da ju je Amra poslala sa svog telefona.
  Future<void> placeFromOtherPhone(
    WidgetTester tester,
    String id, {
    String? table,
    Map<String, int> items = const {'KAFA': 2},
    String? note,
  }) async {
    await tester.runAsync(() async {
      final amra = FakeBackend(server, serverDb, orders: orders);
      await amra.login(testVenueCode, '1111');
      final ids = {for (final i in await server.items()) i.name: i.id};
      final tableId = table == null
          ? null
          : (await server.tables()).firstWhere((t) => t.name == table).id;
      await amra.placeOrder(
        NewOrder(
          id: id,
          tableId: tableId,
          note: note,
          quantities: {for (final e in items.entries) ids[e.key]!: e.value},
        ),
      );
    });
  }

  testWidgets('konobar bira sto, kuca artikle i šalje narudžbu na šank', (
    tester,
  ) async {
    await setUpPhone(tester);
    await tester.runAsync(() => server.addTables(['Sto 1', 'Sto 2']));
    await login(tester, '1111');

    expect(find.text('NARUDŽBA'), findsOneWidget);
    expect(find.text('OBRAČUN'), findsOneWidget);
    await tapText(tester, 'NARUDŽBA');
    expect(find.text('Izaberite sto'), findsOneWidget);
    expect(find.text('Bez stola'), findsOneWidget);
    await tapText(tester, 'Sto 2');

    await tapText(tester, 'KAFA');
    await tapText(tester, 'KAFA');
    await tapText(tester, 'KOLA');
    await tester.longPress(find.text('KOLA'));
    await tester.pumpAndSettle();
    expect(find.text('Naruči · 2 kom · ${fmtKm(500)}'), findsOneWidget);
    await tapText(tester, 'KOLA');
    expect(find.text('Naruči · 3 kom · ${fmtKm(850)}'), findsOneWidget);

    await tapText(tester, 'Napomena');
    await tester.enterText(find.byType(TextField), 'kafa bez šećera');
    await tapText(tester, 'Spremi');
    await tapText(tester, 'Naruči · 3 kom · ${fmtKm(850)}');
    expect(find.text('Poslano na šank: Sto 2'), findsOneWidget);
    expect(find.text('Izaberite sto'), findsOneWidget, reason: 'sljedeći sto');
    expect(orders.single.tableName, 'Sto 2');
    expect(orders.single.note, 'kafa bez šećera');
    expect(orders.single.lines.map((l) => '${l.qty}× ${l.name}'), [
      '2× KAFA',
      '1× KOLA',
    ]);

    // Bez interneta narudžba ostaje u korpi; ponovljeno slanje ne pravi duplikat.
    await tapText(tester, 'Bez stola');
    await tapText(tester, 'ČAJ');
    backend.offline = true;
    await tapText(tester, 'Naruči · 1 kom · ${fmtKm(300)}');
    expect(find.textContaining('Narudžba nije poslana'), findsOneWidget);
    await tapText(tester, 'U redu');
    backend.offline = false;
    await tapText(tester, 'Naruči · 1 kom · ${fmtKm(300)}');
    expect(find.text('Poslano na šank: Narudžba 2'), findsOneWidget);
    expect(orders, hasLength(2));

    await tapText(tester, 'Moje');
    expect(find.text('Danas 2 narudžbe · ${fmtKm(1150)}'), findsOneWidget);
    expect(find.text('Šank sprema'), findsNWidgets(2));
  });

  testWidgets('lokal bez stolova kuca odmah artikle', (tester) async {
    await setUpPhone(tester);
    await login(tester, '1111');
    await tapText(tester, 'NARUDŽBA');
    expect(find.text('Izaberite sto'), findsNothing);
    await tapText(tester, 'KOLA');
    await tapText(tester, 'Naruči · 1 kom · ${fmtKm(350)}');
    expect(find.text('Poslano na šank: Narudžba 1'), findsOneWidget);
  });

  testWidgets('šank vidi narudžbe, otvara ih i povlačenjem završava', (
    tester,
  ) async {
    await setUpPhone(tester);
    await tester.runAsync(() => server.addTables(['Sto 2']));
    await placeFromOtherPhone(
      tester,
      'n1',
      table: 'Sto 2',
      items: {'KAFA': 2, 'KOLA': 1},
      note: 'kafa bez šećera',
    );
    await placeFromOtherPhone(tester, 'n2', items: {'ČAJ': 1});

    await login(tester, '2222');
    expect(find.text('NARUDŽBA'), findsNothing, reason: 'šank ne kuca');
    expect(find.text('Šank · 2 narudžbe čekaju'), findsOneWidget);
    expect(find.text('Sto 2'), findsOneWidget);
    expect(find.text('Narudžba 2'), findsOneWidget);
    expect(find.text('Amra · 3 artikla · napomena'), findsOneWidget);

    // Zatvorena kartica ne pokazuje stavke; tap je otvara.
    expect(find.text('KOLA'), findsNothing);
    await tapText(tester, 'Sto 2');
    expect(find.text('KOLA'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('kafa bez šećera'), findsOneWidget);

    await tester.drag(find.text('Sto 2'), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Gotovo: Sto 2'), findsOneWidget);
    expect(orders.first.isDone, isTrue);
    expect(find.text('Šank · 1 narudžba čeka'), findsOneWidget);

    // Povučeno greškom: vraća se na listu.
    await tapText(tester, 'Poništi');
    expect(orders.first.isDone, isFalse);
    expect(find.text('Šank · 2 narudžbe čekaju'), findsOneWidget);

    // Nova narudžba se pojavi sama.
    await placeFromOtherPhone(tester, 'n3', items: {'KOLA': 1});
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Narudžba 3'), findsOneWidget);
    expect(find.text('Šank · 3 narudžbe čekaju'), findsOneWidget);
  });
}
