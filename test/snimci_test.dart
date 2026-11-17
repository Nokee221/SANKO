// Video snimci ekrana šanka, kadar po kadar. Pokreće se samo na zahtjev:
//   SANKO_VIDEO=<folder> flutter test test/snimci_test.dart
// U <folder>/<snimak>/ ostaju PNG kadrovi (30 u sekundi) i dodiri.json, od kojih
// tool/snimci_u_video.py pravi MP4.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/orders.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/sync/waiter_sync.dart';
import 'package:sanko/waiter_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';
import 'support/shots.dart';

final _out = Platform.environment['SANKO_VIDEO'];
const _frame = Duration(milliseconds: 33);

void main() {
  setUpAll(() async {
    if (_out != null) await loadShotFonts();
  });

  late Database serverDb;
  late Database phoneDb;
  late Repository server;
  late Repository phone;
  late WaiterSync sync;
  late List<Order> orders;
  final screen = GlobalKey();

  Future<void> setUpPhone(WidgetTester tester) async {
    await tester.runAsync(() async {
      serverDb = await openTestDb(isolate: false);
      server = Repository(serverDb);
      await server.addWorker(name: 'Amra', pin: '1111');
      await server.addWorker(name: 'Bakir', pin: '2222', role: WorkerRole.sank);
      await server.seedDemoItems();
      await server.addTables(['Sto 1', 'Sto 2', 'Sto 3', 'Terasa 5']);
      orders = [];
      phoneDb = await openTestDb(isolate: false);
      phone = Repository(phoneDb);
      sync = WaiterSync(
        phone,
        FakeBackend(server, serverDb, orders: orders),
        autoSync: false,
      );
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

  /// Narudžba sa Amrinog telefona; [age] je koliko već čeka.
  Future<void> place(
    WidgetTester tester,
    String id,
    String table,
    Map<String, int> items, {
    String? note,
    Duration age = Duration.zero,
  }) async {
    await tester.runAsync(() async {
      final amra = FakeBackend(server, serverDb, orders: orders);
      await amra.login(testVenueCode, '1111');
      final ids = {for (final i in await server.items()) i.name: i.id};
      final tableId = (await server.tables())
          .firstWhere((t) => t.name == table)
          .id;
      final o = await amra.placeOrder(
        NewOrder(
          id: id,
          tableId: tableId,
          note: note,
          quantities: {for (final e in items.entries) ids[e.key]!: e.value},
        ),
      );
      orders[orders.indexOf(o)] = Order(
        id: o.id,
        number: o.number,
        workerName: o.workerName,
        tableName: o.tableName,
        note: o.note,
        createdAt: o.createdAt.subtract(age),
        lines: o.lines,
      );
    });
  }

  Future<void> loginAsBar(WidgetTester tester) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: screen,
        child: WaiterApp(repo: phone, sync: sync),
      ),
    );
    await tester.pumpAndSettle();
    for (final d in '2222'.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pumpAndSettle();
    }
    // Ekran šanka učitava narudžbe odmah po otvaranju.
    await tester.runAsync(() => Future<void>.delayed(_frame));
    await tester.pumpAndSettle();
  }

  /// Snima kadrove u folder [name]; dodiri se pamte za iscrtavanje prsta.
  ({
    Future<void> Function([int]) frames,
    void Function(String, Offset) touch,
    Future<void> Function() save,
  })
  recorder(WidgetTester tester, String name) {
    final dir = Directory('$_out/$name')..createSync(recursive: true);
    for (final f in dir.listSync()) {
      f.deleteSync();
    }
    var n = 0;
    final touches = <Map<String, Object>>[];
    Future<void> frames([int count = 1]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(_frame);
        final boundary =
            screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${dir.path}/${(n++).toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }

    void touch(String kind, Offset at) =>
        touches.add({'frame': n, 'kind': kind, 'x': at.dx * 2, 'y': at.dy * 2});
    Future<void> save() async =>
        File('${dir.path}/dodiri.json').writeAsStringSync(jsonEncode(touches));
    return (frames: frames, touch: touch, save: save);
  }

  testWidgets('snimak: nova narudžba stiže na šank', (tester) async {
    if (_out == null) return;
    await setUpPhone(tester);
    await loginAsBar(tester);
    final rec = recorder(tester, 'nova_narudzba');

    await rec.frames(45);
    // Konobar šalje narudžbu; telefon na šanku je dobija pri sljedećem osvježavanju.
    await place(tester, 'n1', 'Terasa 5', {
      'KAPUCINO': 2,
      'ČAJ': 1,
      'KOLA': 1,
    }, note: 'jedan kapučino bez šećera');
    await tester.pump(const Duration(milliseconds: 3900));
    await rec.frames(75);

    // Šanker tapne obavještenje i narudžba se otvori.
    final banner = tester.getCenter(find.text('Nova narudžba · Terasa 5'));
    rec.touch('down', banner);
    await rec.frames(6);
    await tester.tap(find.text('Nova narudžba · Terasa 5'));
    rec.touch('up', banner);
    await rec.frames(90);
    await rec.save();
  });

  testWidgets('snimak: povlačenjem se narudžba završava', (tester) async {
    if (_out == null) return;
    await setUpPhone(tester);
    await place(
      tester,
      'n1',
      'Terasa 5',
      {'KAPUCINO': 2, 'ČAJ': 1, 'KOLA': 1},
      note: 'jedan kapučino bez šećera',
      age: const Duration(minutes: 2),
    );
    await loginAsBar(tester);
    await tester.tap(find.text('Terasa 5'));
    await tester.pumpAndSettle();
    final rec = recorder(tester, 'zavrsena_narudzba');

    await rec.frames(45);
    // Prst povlači karticu udesno.
    var at = tester.getCenter(find.text('Terasa 5')) - const Offset(40, 0);
    rec.touch('down', at);
    final gesture = await tester.startGesture(at);
    await rec.frames(4);
    for (var i = 0; i < 16; i++) {
      await gesture.moveBy(const Offset(16, 0));
      at += const Offset(16, 0);
      rec.touch('move', at);
      await rec.frames();
    }
    await gesture.up();
    rec.touch('up', at);
    await rec.frames(100);
    await rec.save();
  });
}
