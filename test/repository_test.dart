import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/db.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/domain/obracun.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late Repository repo;
  var now = DateTime(2025, 7, 30, 7);

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => createSchema(db),
      ),
    );
    now = DateTime(2025, 7, 30, 7);
    repo = Repository(db, now: () => now);
    await repo.addWorker(name: 'Amra', pin: '1111');
    await repo.addWorker(name: 'Bakir', pin: '2222');
    await repo.addItem(
      name: 'KAFA',
      kind: ItemKind.counter,
      price: 250,
      initialQty: 148687,
    );
    await repo.addItem(
      name: 'KOLA',
      kind: ItemKind.stock,
      price: 350,
      initialQty: 77,
    );
    await repo.addItem(
      name: 'ĐUS',
      kind: ItemKind.stock,
      price: 350,
      initialQty: 56,
    );
  });

  tearDown(() => db.close());

  Future<Map<String, String>> itemIds() async => {
    for (final i in await repo.items()) i.name: i.id,
  };

  ObracunLine line(Obracun o, String name) =>
      o.lines.firstWhere((l) => l.name == name);

  test('konobar upisuje prodano; iznos je prodano puta cijena', () async {
    final ids = await itemIds();
    final amra = (await repo.workerByPin('1111'))!;
    final shift = await repo.startShift(amra.id);

    await repo.setSoldQty(shift.id, ids['KOLA']!, 5);
    await repo.setSoldQty(shift.id, ids['KAFA']!, 40);
    var o = await repo.obracunForShift(shift.id);
    expect(line(o, 'KOLA').consumed, 5);
    expect(line(o, 'KOLA').closing, 72);
    expect(line(o, 'KOLA').amount, 5 * 350);
    expect(line(o, 'KAFA').closing, 148727, reason: 'brojač ide naprijed');
    expect(line(o, 'KAFA').amount, 40 * 250);

    // Roba stigla nakon unosa: prodano ostaje 5, raste samo ostatak.
    await repo.setDraftReceiptQty(shift.id, ids['KOLA']!, 24);
    await repo.closeDraftReceipt(shift.id);
    o = await repo.obracunForShift(shift.id);
    expect(line(o, 'KOLA').consumed, 5);
    expect(line(o, 'KOLA').closing, 96);

    // Ne može se prodati više nego što je bilo na šanku.
    await expectLater(
      repo.setSoldQty(shift.id, ids['ĐUS']!, 57),
      throwsA(isA<SankoException>()),
    );
    await repo.setSoldQty(shift.id, ids['ĐUS']!, 56);
    o = await repo.obracunForShift(shift.id);
    expect(o.sank, 5 * 350 + 40 * 250 + 56 * 350);
  });

  test('obračun smjene odgovara primjeru iz knjige šanka', () async {
    final ids = await itemIds();
    final amra = (await repo.workerByPin('1111'))!;
    final shift = await repo.startShift(amra.id);

    await repo.setDraftReceiptQty(shift.id, ids['KOLA']!, 24);
    await repo.setDraftReceiptQty(shift.id, ids['ĐUS']!, -12);
    await repo.closeDraftReceipt(shift.id);
    await repo.addExpense(
      shift.id,
      description: 'Konzum, mlijeko',
      amount: 300,
    );
    await repo.addExpense(shift.id, description: 'Kafa na Bakira', amount: 250);

    await repo.setClosingQty(shift.id, ids['KAFA']!, 149091);
    await repo.setClosingQty(shift.id, ids['KOLA']!, 88);
    await repo.setClosingQty(shift.id, ids['ĐUS']!, 35);
    await repo.closeShift(shift.id);

    final o = await repo.obracunForShift(shift.id);
    expect(line(o, 'KAFA').consumed, 404);
    expect(line(o, 'KAFA').amount, 101000);
    expect(line(o, 'KOLA').total, 101);
    expect(line(o, 'KOLA').consumed, 13);
    expect(line(o, 'KOLA').amount, 4550);
    expect(line(o, 'ĐUS').total, 44);
    expect(line(o, 'ĐUS').consumed, 9);
    expect(o.sank, 101000 + 4550 + 3150);
    expect(o.expenses, 550);
    expect(o.total, o.sank - 550);
  });

  test(
    'druga smjena preuzima stanje prve, a dnevni obračun ih spaja',
    () async {
      final ids = await itemIds();
      final amra = (await repo.workerByPin('1111'))!;
      final bakir = (await repo.workerByPin('2222'))!;

      final first = await repo.startShift(amra.id);
      await repo.setClosingQty(first.id, ids['KAFA']!, 148887);
      await repo.setClosingQty(first.id, ids['KOLA']!, 70);
      await repo.setClosingQty(first.id, ids['ĐUS']!, 50);
      await repo.closeShift(first.id);

      now = DateTime(2025, 7, 30, 15);
      final second = await repo.startShift(bakir.id);
      expect(second.seq, 2);
      await repo.setDraftReceiptQty(second.id, ids['KOLA']!, 24);
      await repo.closeDraftReceipt(second.id);
      await repo.setClosingQty(second.id, ids['KAFA']!, 149091);
      await repo.setClosingQty(second.id, ids['KOLA']!, 82);
      await repo.setClosingQty(second.id, ids['ĐUS']!, 47);
      await repo.closeShift(second.id);

      final o2 = await repo.obracunForShift(second.id);
      expect(line(o2, 'KOLA').opening, 70);
      expect(line(o2, 'KAFA').opening, 148887);

      final day = await repo.obracunForDay(DateTime(2025, 7, 30));
      expect(line(day, 'KAFA').opening, 148687);
      expect(line(day, 'KAFA').closing, 149091);
      expect(line(day, 'KAFA').consumed, 404);
      expect(line(day, 'KOLA').received, 24);
      expect(line(day, 'KOLA').consumed, 7 + 12);
      expect(line(day, 'ĐUS').consumed, 6 + 3);
      expect(day.sank, 404 * 250 + 19 * 350 + 9 * 350);
      expect(
        (await repo.shiftsOn(DateTime(2025, 7, 30))).map((s) => s.workerName),
        ['Amra', 'Bakir'],
      );
    },
  );

  test(
    'smjena se ne može zaključiti bez svih stanja ni sa nezaključenim ulazom',
    () async {
      final ids = await itemIds();
      final shift = await repo.startShift((await repo.workerByPin('1111'))!.id);
      await repo.setClosingQty(shift.id, ids['KAFA']!, 148700);
      await repo.setClosingQty(shift.id, ids['KOLA']!, 70);
      await expectLater(
        repo.closeShift(shift.id),
        throwsA(isA<SankoException>()),
      );

      await repo.setClosingQty(shift.id, ids['ĐUS']!, 50);
      await repo.setDraftReceiptQty(shift.id, ids['KOLA']!, 24);
      await expectLater(
        repo.closeShift(shift.id),
        throwsA(isA<SankoException>()),
      );

      // Nezaključen ulaz ne ulazi u obračun.
      expect(line(await repo.obracunForShift(shift.id), 'KOLA').received, 0);

      await repo.setDraftReceiptQty(shift.id, ids['KOLA']!, null);
      await repo.closeShift(shift.id);
      expect((await repo.shiftById(shift.id)).isClosed, isTrue);
    },
  );

  test('zaključena smjena se ne može mijenjati', () async {
    final ids = await itemIds();
    final shift = await repo.startShift((await repo.workerByPin('1111'))!.id);
    for (final e in {'KAFA': 148700, 'KOLA': 70, 'ĐUS': 50}.entries) {
      await repo.setClosingQty(shift.id, ids[e.key]!, e.value);
    }
    await repo.closeShift(shift.id);

    await expectLater(
      repo.setClosingQty(shift.id, ids['KOLA']!, 77),
      throwsA(isA<SankoException>()),
    );
    await expectLater(
      repo.setDraftReceiptQty(shift.id, ids['KOLA']!, 5),
      throwsA(isA<SankoException>()),
    );
    await expectLater(
      repo.addExpense(shift.id, description: 'x', amount: 100),
      throwsA(isA<SankoException>()),
    );
  });

  test('samo jedna smjena može biti otvorena', () async {
    await repo.startShift((await repo.workerByPin('1111'))!.id);
    await expectLater(
      repo.startShift((await repo.workerByPin('2222'))!.id),
      throwsA(
        isA<SankoException>().having(
          (e) => e.message,
          'message',
          contains('Amra'),
        ),
      ),
    );
  });

  test('brojač ne može ići unazad, a višak na zalihi se označava', () async {
    final ids = await itemIds();
    final shift = await repo.startShift((await repo.workerByPin('1111'))!.id);
    await expectLater(
      repo.setClosingQty(shift.id, ids['KAFA']!, 148000),
      throwsA(isA<SankoException>()),
    );
    await repo.setClosingQty(shift.id, ids['KOLA']!, 80);
    expect(
      line(await repo.obracunForShift(shift.id), 'KOLA').hasAnomaly,
      isTrue,
    );
  });

  test('PIN je jedinstven i oslobađa se brisanjem radnika', () async {
    await expectLater(
      repo.addWorker(name: 'Ceca', pin: '1111'),
      throwsA(isA<SankoException>()),
    );
    await expectLater(
      repo.addWorker(name: 'Ceca', pin: '12a4'),
      throwsA(isA<SankoException>()),
    );
    await repo.removeWorker((await repo.workerByPin('1111'))!.id);
    expect(await repo.workerByPin('1111'), isNull);
    await repo.addWorker(name: 'Ceca', pin: '1111');
    expect((await repo.workers()).map((w) => w.name), ['Bakir', 'Ceca']);
  });

  test(
    'artikal dodan usred smjene ulazi u nju, obrisan ostaje u njoj',
    () async {
      final ids = await itemIds();
      final shift = await repo.startShift((await repo.workerByPin('1111'))!.id);
      await repo.addItem(
        name: 'FANTA',
        kind: ItemKind.stock,
        price: 350,
        initialQty: 42,
      );
      await repo.removeItem(ids['ĐUS']!);

      final o = await repo.obracunForShift(shift.id);
      expect(o.lines.map((l) => l.name), ['KAFA', 'KOLA', 'ĐUS', 'FANTA']);
      expect(line(o, 'FANTA').opening, 42);
      expect((await repo.items()).map((i) => i.name), [
        'KAFA',
        'KOLA',
        'FANTA',
      ]);
    },
  );

  test(
    'predaja: manjak se računa, gazda ga ispravlja i ispravka se zapisuje',
    () async {
      final ids = await itemIds();
      final amra = (await repo.workerByPin('1111'))!;
      final shift = await repo.startShift(amra.id);
      await repo.addExpense(shift.id, description: 'Mlijeko', amount: 300);
      await repo.setClosingQty(shift.id, ids['KAFA']!, 148787);
      await repo.setClosingQty(shift.id, ids['KOLA']!, 67);
      await repo.setClosingQty(shift.id, ids['ĐUS']!, 56);
      await expectLater(
        repo.closeShift(
          shift.id,
          handover: const Handover(kitchen: -1, cash: 0, card: 0),
        ),
        throwsA(isA<SankoException>()),
      );
      // 100 kafa i 10 kola = 285,00; kuhinja 40,00; rashod 3,00.
      await repo.closeShift(
        shift.id,
        handover: const Handover(kitchen: 4000, cash: 25000, card: 6200),
      );

      var o = await repo.obracunForShift(shift.id);
      expect(o.sank, 28500);
      expect(o.total, 28500 + 4000 - 300);
      expect(o.handedOver, 31200);
      expect(o.difference, -1000);

      await repo.setHandover(
        shift.id,
        const Handover(kitchen: 4000, cash: 26000, card: 6200),
        note: 'Donio ostatak',
      );
      o = await repo.obracunForShift(shift.id);
      expect(o.difference, 0);
      final corrections = await repo.corrections([shift.id]);
      expect(corrections.single.field, CorrectionField.cash);
      expect(corrections.single.oldValue, 25000);
      expect(corrections.single.newValue, 26000);

      final summary = (await repo.shiftSummaries(
        DateTime(2025, 7, 1),
        DateTime(2025, 7, 31),
      )).single;
      expect(summary.revenue, 28500 + 4000);
      expect(summary.difference, 0);
      expect(summary.workerName, 'Amra');
    },
  );

  test(
    'smjena bez predaje nema razliku, a dan sabira samo smjene s predajom',
    () async {
      final ids = await itemIds();
      final amra = (await repo.workerByPin('1111'))!;
      final bakir = (await repo.workerByPin('2222'))!;
      final first = await repo.startShift(amra.id);
      await repo.setClosingQty(first.id, ids['KAFA']!, 148787);
      await repo.setClosingQty(first.id, ids['KOLA']!, 77);
      await repo.setClosingQty(first.id, ids['ĐUS']!, 56);
      await repo.closeShift(first.id);
      expect((await repo.obracunForShift(first.id)).difference, isNull);

      now = DateTime(2025, 7, 30, 15);
      final second = await repo.startShift(bakir.id);
      await repo.setClosingQty(second.id, ids['KAFA']!, 148887);
      await repo.setClosingQty(second.id, ids['KOLA']!, 77);
      await repo.setClosingQty(second.id, ids['ĐUS']!, 56);
      await repo.closeShift(
        second.id,
        handover: const Handover(kitchen: 0, cash: 24000, card: 0),
      );

      final day = await repo.obracunForDay(DateTime(2025, 7, 30));
      expect(day.sank, 50000);
      expect(day.handedOver, 24000);
      // Bakir je predao 10 KM manje od svojih 250 KM; Amrina smjena nema predaju.
      expect(day.difference, -1000);
    },
  );
}
