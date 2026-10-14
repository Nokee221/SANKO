// Prolazi kroz cijelu smjenu preko ekrana telefona, pa provjerava admin panel nad "serverom".
// Sa SANKO_SHOTS=1 i --update-goldens usput snima slike ekrana u test/shots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sanko/app.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/sync/waiter_sync.dart';
import 'package:sanko/ui/admin/admin_shell.dart';
import 'package:sanko/ui/admin/scope.dart';
import 'package:sanko/ui/format.dart';
import 'package:sanko/waiter_app.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

final _shots = Platform.environment['SANKO_SHOTS'] == '1';

Future<void> _loadFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> font(String name) async =>
      ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final manrope = FontLoader('Manrope');
  for (final w in [400, 500, 600, 700, 800]) {
    manrope.addFont(
      File(
        'assets/fonts/Manrope-$w.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await manrope.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(font('MaterialIcons-Regular.otf'))).load();
}

Future<void> _shot(String name) async {
  if (!_shots) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/$name.png'),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('smjena od prijave do obračuna, pa admin panel', (tester) async {
    late Database serverDb;
    late Database phoneDb;
    late Repository server;
    late Repository phone;
    late FakeBackend backend;
    late WaiterSync sync;
    await tester.runAsync(() async {
      serverDb = await openTestDb(isolate: false);
      server = Repository(serverDb);
      await server.addWorker(name: 'Amra', pin: '1111');
      await server.addWorker(name: 'Bakir', pin: '2222');
      await server.seedDemoItems();

      // Probne slike iz kataloga, vezane za artikle istog naziva.
      final images = [
        for (final f in Directory(
          'supabase/slike',
        ).listSync().whereType<File>())
          CatalogImage(
            id: 'slika-${path.basenameWithoutExtension(f.path)}',
            name: path.basenameWithoutExtension(f.path),
            bytes: await f.readAsBytes(),
          ),
      ];
      await server.saveImages(images);
      for (final item in await server.items()) {
        final image = images.where((i) => i.name == item.name).firstOrNull;
        await server.updateItem(
          Item(
            id: item.id,
            name: item.name,
            kind: item.kind,
            price: item.price,
            initialQty: item.initialQty,
            imageId: image?.id,
          ),
        );
      }

      phoneDb = await openTestDb(isolate: false);
      phone = Repository(phoneDb);
      backend = FakeBackend(server, serverDb);
      sync = WaiterSync(phone, backend, autoSync: false);
      await sync.init();
    });
    addTearDown(() async {
      await phoneDb.close();
      await serverDb.close();
    });
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;

    // Slike se dekodiraju izvan lažnog sata testa; ovo im daje vremena prije snimka.
    Future<void> settleImages() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapText(String text) async {
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }

    Future<void> enterPin(String pin) async {
      for (final d in pin.split('')) {
        await tapText(d);
      }
    }

    Future<void> enterQty(
      String item,
      String digits, {
      bool negative = false,
    }) async {
      await tapText(item);
      for (final d in digits.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      if (negative) await tapText('+/−');
      await tapText('Potvrdi');
    }

    await tester.pumpWidget(WaiterApp(repo: phone, sync: sync));
    await tester.pumpAndSettle();

    // Prvo pokretanje traži kod lokala.
    expect(find.textContaining('Unesite kod lokala'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'test01');
    await tester.pump();
    await _shot('00_kod_lokala');
    await tapText('Dalje');
    expect(find.text('Unesite svoj PIN'), findsOneWidget);
    await _shot('01_pin');

    await enterPin('9999');
    expect(find.text('Pogrešan kod lokala ili PIN.'), findsOneWidget);

    await enterPin('1111');
    expect(find.text('Započni smjenu'), findsOneWidget);
    await tapText('Započni smjenu');
    expect(find.text('ULAZ'), findsOneWidget);
    expect(find.text('0/33'), findsOneWidget);
    expect(find.text('Sve je poslano na server'), findsOneWidget);
    await _shot('02_pocetna');

    // Od sada telefon nema mrežu; sve se unosi lokalno.
    backend.offline = true;

    // ULAZ
    await tapText('ULAZ');
    expect(find.text('KAFA'), findsNothing, reason: 'brojač nema ulaz');
    await enterQty('KAPUCINO', '32');
    await enterQty('ĐUS', '12', negative: true);
    await tapText('KOLA');
    await tester.tap(find.text('2').last);
    await tester.tap(find.text('4').last);
    await tester.pump();
    await _shot('03_ulaz_unos');
    await tapText('Potvrdi');
    expect(find.text('+24'), findsOneWidget);
    expect(find.text('-12'), findsOneWidget);
    await settleImages();
    await _shot('04_ulaz');
    await tapText('Zaključi ulaz (3)');
    await _shot('05_ulaz_potvrda');
    await tapText('Zaključi ulaz');
    expect(find.text('zaključeno'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // RASHOD
    await tapText('RASHOD');
    await tester.enterText(find.byType(TextField).at(0), 'Konzum, mlijeko');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tapText('Dodaj');
    await tester.enterText(find.byType(TextField).at(0), 'Kafa na Bakira');
    await tester.enterText(find.byType(TextField).at(1), '2,5');
    await tapText('Dodaj');
    expect(find.text('5,50 KM'), findsOneWidget);
    await _shot('06_rashod');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('5,50'), findsOneWidget);

    // STANJE
    await tapText('STANJE');
    await tapText('KAFA');
    expect(find.text('Prethodno stanje brojača: 148687'), findsOneWidget);
    await tester.tap(find.text('5').last);
    await tester.pump();
    await tapText('Potvrdi');
    expect(find.textContaining('Brojač ne može biti manji'), findsOneWidget);
    await tapText('U redu');
    await enterQty('KAFA', '149091');
    await enterQty('KAPUCINO', '42');
    await enterQty('ČAJ', '207');
    expect(find.text('Uneseno 3 od 33'), findsOneWidget);
    expect(find.text('Još 30 za unijeti'), findsOneWidget);
    await settleImages();
    await _shot('07_stanje');

    // Ostatak brojanja ide direktno u bazu telefona: sve ostaje kako je bilo, osim kole i đusa.
    final shift = (await tester.runAsync(phone.openShift))!;
    await tester.runAsync(() async {
      final o = await phone.obracunForShift(shift.id);
      for (final l in o.lines.where((l) => l.closing == null)) {
        final sold = switch (l.name) {
          'KOLA' => 13,
          'ĐUS' => 9,
          _ => 0,
        };
        await phone.setClosingQty(shift.id, l.itemId, l.total - sold);
      }
    });
    await tester.pumpAndSettle();
    await tapText('Zaključi smjenu');
    await tapText('Zaključi smjenu');

    // 404 kafe, 30 kapučina, 7 čajeva, 13 kola, 9 đusa.
    const sank = 404 * 250 + 30 * 350 + 7 * 300 + 13 * 350 + 9 * 350;
    expect(find.text('Smjena zaključena'), findsOneWidget);
    expect(find.text(fmtKm(sank)), findsOneWidget);
    expect(find.text(fmtKm(sank - 550)), findsOneWidget);

    // Bez mreže smjena čeka na telefonu; server je još vidi kao otvorenu.
    await tester.runAsync(sync.pushNow);
    await tester.pumpAndSettle();
    expect(find.textContaining('Čeka slanje na server'), findsOneWidget);
    expect(
      (await tester.runAsync(() => server.shiftById(shift.id)))!.isClosed,
      isFalse,
    );
    await _shot('08_obracun_ceka_slanje');

    backend.offline = false;
    await tester.runAsync(sync.pushNow);
    await tester.pumpAndSettle();
    expect(find.text('Sve je poslano na server'), findsOneWidget);
    expect(
      (await tester.runAsync(() => server.shiftById(shift.id)))!.isClosed,
      isTrue,
    );
    await _shot('09_obracun_poslano');
    await tapText('Odjava');
    expect(find.text('Unesite svoj PIN'), findsOneWidget);

    // Bakir na svom telefonu otvara drugu smjenu, pa je Amra ne može započeti.
    await tester.runAsync(() async {
      final other = FakeBackend(server, serverDb);
      await other.login(testVenueCode, '2222');
      await other.startShift('nova');
    });
    await enterPin('1111');
    await tapText('Započni smjenu');
    expect(
      find.textContaining('Smjenu još nije zaključio/la Bakir'),
      findsOneWidget,
    );
    await tapText('U redu');

    // Admin panel nad serverom
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpWidget(
      AdminScope(
        key: UniqueKey(),
        data: server,
        child: const SankoMaterialApp(home: AdminShell()),
      ),
    );
    // Slika znaka se učitava izvan lažnog sata testa.
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/logo.png'),
        tester.element(find.byType(AdminShell)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Smjena 1, Amra'), findsOneWidget);
    expect(find.textContaining('Smjena 2, Bakir'), findsOneWidget);
    expect(find.textContaining('još nije zaključena'), findsOneWidget);
    await _shot('10_admin_dan');

    // Gazda zaključuje Bakirovu smjenu, jer je konobar ne može zaključiti sam.
    await tapText('Zaključi smjenu');
    expect(find.textContaining('Zaključiti smjenu 2 (Bakir)?'), findsOneWidget);
    await tapText('Zaključi smjenu');
    expect(find.textContaining('Unesite stanje za'), findsOneWidget);
    await tapText('U redu');
    await _shot('10b_admin_zakljucenje');
    await tapText('Popuni prazna polja kao da nije bilo prodaje');
    await tapText('Zaključi smjenu');
    expect(find.textContaining('još nije zaključena'), findsNothing);
    expect((await tester.runAsync(server.openShift)), isNull);

    await tester.tap(find.textContaining('Smjena 1, Amra'));
    await tester.pumpAndSettle();
    expect(find.text(fmtMoney(sank)), findsOneWidget);
    expect(find.text(fmtMoney(sank - 550)), findsOneWidget);
    expect(find.text('Konzum, mlijeko'), findsOneWidget);
    await _shot('11_admin_smjena');
    await tapText('Ispravi smjenu');
    await _shot('11c_admin_ispravka');
    await tapText('Odustani');

    await tapText('Prosjek');
    expect(find.textContaining('Zadnjih 30 dana:'), findsOneWidget);
    await _shot('11b_admin_prosjek');
    await tapText('Artikli');
    expect(find.text('KAFA'), findsOneWidget);
    await tester.tap(find.byTooltip('Izmijeni').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Artikal je već bio u smjeni'), findsOneWidget);
    await tapText('Odustani');
    await settleImages();
    await _shot('12_admin_artikli');
    await tapText('Radnici');
    expect(find.text('Amra'), findsOneWidget);
    await _shot('13_admin_radnici');
  });
}
