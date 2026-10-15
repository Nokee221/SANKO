import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/domain/obracun.dart';
import 'package:sanko/sync/waiter_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

/// Jedan telefon: svoja lokalna baza i svoja veza sa serverom.
class Phone {
  Phone(this.db, this.repo, this.backend, this.sync);

  final Database db;
  final Repository repo;
  final FakeBackend backend;
  final WaiterSync sync;
}

void main() {
  late Database serverDb;
  late Repository server;
  final phones = <Phone>[];

  Future<Phone> newPhone() async {
    final db = await openTestDb();
    final repo = Repository(db);
    final backend = FakeBackend(server, serverDb);
    final sync = WaiterSync(repo, backend, autoSync: false);
    await sync.init();
    await sync.setVenueCode(testVenueCode);
    final phone = Phone(db, repo, backend, sync);
    phones.add(phone);
    return phone;
  }

  setUp(() async {
    serverDb = await openTestDb();
    server = Repository(serverDb);
    await server.addWorker(name: 'Amra', pin: '1111');
    await server.addWorker(name: 'Bakir', pin: '2222');
    await server.addItem(
      name: 'KAFA',
      kind: ItemKind.counter,
      price: 250,
      initialQty: 148687,
    );
    await server.addItem(
      name: 'KOLA',
      kind: ItemKind.stock,
      price: 350,
      initialQty: 77,
    );
  });

  tearDown(() async {
    for (final p in phones) {
      p.sync.dispose();
      await p.db.close();
    }
    phones.clear();
    await serverDb.close();
  });

  ObracunLine line(Obracun o, String name) =>
      o.lines.firstWhere((l) => l.name == name);

  Future<void> count(Phone p, String shiftId, Map<String, int> counts) async {
    final o = await p.repo.obracunForShift(shiftId);
    for (final e in counts.entries) {
      await p.repo.setClosingQty(shiftId, line(o, e.key).itemId, e.value);
    }
  }

  test('smjena unesena bez mreže stiže na server kad se mreža vrati', () async {
    final phone = await newPhone();
    final amra = await phone.sync.login('1111');
    final shift = await phone.sync.startShift(amra);
    expect(
      (await phone.repo.obracunForShift(shift.id)).lines.map((l) => l.name),
      ['KAFA', 'KOLA'],
    );

    phone.backend.offline = true;
    final kola = line(
      await phone.repo.obracunForShift(shift.id),
      'KOLA',
    ).itemId;
    await phone.repo.setDraftReceiptQty(shift.id, kola, 24);
    await phone.repo.closeDraftReceipt(shift.id);
    await phone.repo.addExpense(
      shift.id,
      description: 'Konzum, mlijeko',
      amount: 300,
    );
    await count(phone, shift.id, {'KAFA': 149091, 'KOLA': 88});
    await phone.repo.closeShift(
      shift.id,
      handover: const Handover(kitchen: 1500, cash: 100000, card: 6000),
    );
    await phone.sync.pushNow();

    expect(phone.sync.hasUnsent, isTrue);
    expect((await server.shiftById(shift.id)).isClosed, isFalse);

    phone.backend.offline = false;
    await phone.sync.pushNow();

    expect(phone.sync.hasUnsent, isFalse);
    expect((await server.shiftById(shift.id)).isClosed, isTrue);
    final o = await server.obracunForShift(shift.id);
    expect(line(o, 'KAFA').consumed, 404);
    expect(line(o, 'KOLA').received, 24);
    expect(line(o, 'KOLA').consumed, 13);
    expect(o.sank, 404 * 250 + 13 * 350);
    expect(o.expenses, 300);
    // Kuhinja i predaja stižu sa smjenom: za predati 1.068,50, predano 1.060,00.
    expect(o.kitchen, 1500);
    expect(o.total, o.sank + 1500 - 300);
    expect(o.handedOver, 106000);
    expect(o.difference, 106000 - o.total);
  });

  test(
    'druga smjena čeka da prva stigne na server i preuzima njeno stanje',
    () async {
      final first = await newPhone();
      final second = await newPhone();
      final amra = await first.sync.login('1111');
      final bakir = await second.sync.login('2222');
      final shift = await first.sync.startShift(amra);

      first.backend.offline = true;
      await count(first, shift.id, {'KAFA': 148800, 'KOLA': 70});
      await first.repo.closeShift(shift.id);
      await first.sync.pushNow();

      await expectLater(
        second.sync.startShift(bakir),
        throwsA(
          isA<SankoException>().having(
            (e) => e.message,
            'message',
            contains('Amra'),
          ),
        ),
      );

      first.backend.offline = false;
      await first.sync.pushNow();
      final next = await second.sync.startShift(bakir);

      final o = await second.repo.obracunForShift(next.id);
      expect(next.seq, 2);
      expect(line(o, 'KAFA').opening, 148800);
      expect(line(o, 'KOLA').opening, 70);
    },
  );

  test(
    'bez mreže se prijavljuje samo radnik koji se već prijavio na tom telefonu',
    () async {
      final phone = await newPhone();
      phone.backend.offline = true;
      await expectLater(
        phone.sync.login('1111'),
        throwsA(isA<SankoException>()),
      );

      phone.backend.offline = false;
      await phone.sync.login('1111');
      phone.backend.offline = true;

      expect((await phone.sync.login('1111')).name, 'Amra');
      await expectLater(
        phone.sync.login('2222'),
        throwsA(isA<SankoException>()),
      );
      await expectLater(
        phone.sync.startShift(await phone.sync.login('1111')),
        throwsA(
          isA<SankoException>().having(
            (e) => e.message,
            'message',
            contains('internet'),
          ),
        ),
      );
    },
  );

  test('obrisan radnik se više ne može prijaviti ni bez mreže', () async {
    final phone = await newPhone();
    final amra = await phone.sync.login('1111');
    await server.removeWorker(amra.id);

    await expectLater(phone.sync.login('1111'), throwsA(isA<SankoException>()));
    phone.backend.offline = true;
    await expectLater(phone.sync.login('1111'), throwsA(isA<SankoException>()));
  });

  test('novi telefon nastavlja otvorenu smjenu bez gubitka unosa', () async {
    final old = await newPhone();
    final amra = await old.sync.login('1111');
    final shift = await old.sync.startShift(amra);
    await old.repo.addExpense(shift.id, description: 'Limun', amount: 500);
    await count(old, shift.id, {'KAFA': 148700});
    await old.sync.pushNow();

    final fresh = await newPhone();
    final resumed = await fresh.sync.startShift(await fresh.sync.login('1111'));

    expect(resumed.id, shift.id);
    final o = await fresh.repo.obracunForShift(shift.id);
    expect(line(o, 'KAFA').closing, 148700);
    expect(o.expenses, 500);

    // Prvo slanje s novog telefona ne smije obrisati ono što je već na serveru.
    await count(fresh, shift.id, {'KOLA': 70});
    await fresh.sync.pushNow();
    final onServer = await server.obracunForShift(shift.id);
    expect(onServer.expenses, 500);
    expect(line(onServer, 'KAFA').closing, 148700);
    expect(line(onServer, 'KOLA').closing, 70);
  });

  test('artikal koji gazda doda usred smjene stiže na telefon', () async {
    final phone = await newPhone();
    final shift = await phone.sync.startShift(await phone.sync.login('1111'));
    await server.addItem(
      name: 'FANTA',
      kind: ItemKind.stock,
      price: 350,
      initialQty: 42,
    );

    await count(phone, shift.id, {'KOLA': 70});
    await phone.sync.pushNow();

    final o = await phone.repo.obracunForShift(shift.id);
    expect(o.lines.map((l) => l.name), ['KAFA', 'KOLA', 'FANTA']);
    expect(line(o, 'FANTA').opening, 42);
    expect(line(o, 'KOLA').closing, 70);
  });

  test('slike artikala stižu na telefon i ostaju na njemu bez mreže', () async {
    final kolaImage = CatalogImage(
      id: 'slika-kola',
      name: 'KOLA',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    final fantaImage = CatalogImage(
      id: 'slika-fanta',
      name: 'FANTA',
      bytes: Uint8List.fromList([4, 5, 6]),
    );
    await server.saveImages([kolaImage, fantaImage]);
    final kola = (await server.items()).firstWhere((i) => i.name == 'KOLA');
    await server.updateItem(
      Item(
        id: kola.id,
        name: kola.name,
        kind: kola.kind,
        price: kola.price,
        initialQty: kola.initialQty,
        imageId: kolaImage.id,
      ),
    );

    final phone = await newPhone();
    final shift = await phone.sync.startShift(await phone.sync.login('1111'));
    expect((await phone.repo.lineImages(shift.id))[kola.id], [1, 2, 3]);

    // Gazda usred smjene doda artikal sa slikom; stiže pri sljedećem slanju.
    await server.addItem(
      name: 'FANTA',
      kind: ItemKind.stock,
      price: 350,
      imageId: fantaImage.id,
    );
    await count(phone, shift.id, {'KOLA': 70});
    await phone.sync.pushNow();
    final fanta = line(await phone.repo.obracunForShift(shift.id), 'FANTA');

    phone.backend.offline = true;
    final images = await phone.repo.lineImages(shift.id);
    expect(images[fanta.itemId], [4, 5, 6]);
    expect(images.length, 2);
  });

  test('smjenu koju zaključi gazda telefon preuzima kao zaključenu', () async {
    final phone = await newPhone();
    final amra = await phone.sync.login('1111');
    final shift = await phone.sync.startShift(amra);
    final lines = (await phone.repo.obracunForShift(shift.id)).lines;
    await phone.repo.addExpense(shift.id, description: 'Limun', amount: 500);
    await phone.repo.setDraftReceiptQty(
      shift.id,
      line(await phone.repo.obracunForShift(shift.id), 'KOLA').itemId,
      24,
    );
    await phone.sync.pushNow();

    // Konobar je otišao; gazda unosi stanje i zaključuje.
    await server.adminCloseShift(shift.id, {
      for (final l in lines) l.itemId: l.name == 'KAFA' ? 148700 : 70,
    });
    expect((await server.shiftById(shift.id)).isClosed, isTrue);

    // Telefon to sazna pri sljedećoj prijavi i više nema otvorenu smjenu.
    await phone.sync.login('1111');
    await phone.sync.pendingRefresh;
    expect(await phone.repo.openShift(), isNull);
    final o = await phone.repo.obracunForShift(shift.id);
    expect(line(o, 'KAFA').closing, 148700);
    expect(line(o, 'KOLA').closing, 70);
    expect(line(o, 'KOLA').received, 0, reason: 'nezaključen ulaz je odbačen');
    expect(o.expenses, 500);
    expect(phone.sync.hasUnsent, isFalse);

    // Sljedeći konobar može početi.
    final other = await newPhone();
    final next = await other.sync.startShift(await other.sync.login('2222'));
    expect(next.seq, 2);
  });

  test(
    'ispravka prethodne smjene mijenja početno stanje otvorene smjene na telefonu',
    () async {
      final first = await newPhone();
      final s1 = await first.sync.startShift(await first.sync.login('1111'));
      await count(first, s1.id, {'KAFA': 148800, 'KOLA': 70});
      await first.repo.closeShift(s1.id);
      await first.sync.pushNow();

      final second = await newPhone();
      final bakir = await second.sync.login('2222');
      final s2 = await second.sync.startShift(bakir);
      expect(
        line(await second.repo.obracunForShift(s2.id), 'KOLA').opening,
        70,
      );

      final kola = line(await server.obracunForShift(s1.id), 'KOLA').itemId;
      await server.correctShift(s1.id, [
        ItemCorrection(itemId: kola, closing: 66),
      ]);

      await second.sync.login('2222');
      await second.sync.pendingRefresh;
      expect(
        line(await second.repo.obracunForShift(s2.id), 'KOLA').opening,
        66,
      );
    },
  );

  test(
    'zamijenjena slika u katalogu stiže na telefon pri sljedećoj prijavi',
    () async {
      final old = CatalogImage(
        id: 'slika-kola',
        name: 'KOLA',
        bytes: Uint8List.fromList([1, 1, 1]),
      );
      await server.saveImages([old]);
      final kola = (await server.items()).firstWhere((i) => i.name == 'KOLA');
      await server.updateItem(
        Item(
          id: kola.id,
          name: kola.name,
          kind: kola.kind,
          price: kola.price,
          initialQty: kola.initialQty,
          imageId: old.id,
        ),
      );
      final phone = await newPhone();
      final shift = await phone.sync.startShift(await phone.sync.login('1111'));
      expect((await phone.repo.lineImages(shift.id))[kola.id], [1, 1, 1]);

      // Prodavac zamijeni probnu sliku pravom, pod istim nazivom i oznakom.
      await server.saveImages([
        CatalogImage(
          id: old.id,
          name: 'KOLA',
          bytes: Uint8List.fromList([2, 2, 2]),
        ),
      ]);
      await phone.sync.login('1111');
      await phone.sync.pendingRefresh;
      expect((await phone.repo.lineImages(shift.id))[kola.id], [2, 2, 2]);
    },
  );

  test(
    'osvježavanje donosi artikal koji je gazda dodao usred smjene, bez slanja unosa',
    () async {
      final phone = await newPhone();
      final shift = await phone.sync.startShift(await phone.sync.login('1111'));
      await server.addItem(
        name: 'FANTA',
        kind: ItemKind.stock,
        price: 350,
        initialQty: 42,
      );
      expect(
        (await phone.repo.obracunForShift(shift.id)).lines.map((l) => l.name),
        ['KAFA', 'KOLA'],
      );

      expect(await phone.sync.refresh(), isNull);
      expect(
        (await phone.repo.obracunForShift(shift.id)).lines.map((l) => l.name),
        ['KAFA', 'KOLA', 'FANTA'],
      );

      phone.backend.offline = true;
      expect(await phone.sync.refresh(), contains('Nema interneta'));
    },
  );
}
