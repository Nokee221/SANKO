// Admin panel na telefonu gazde: svaka stranica i dijalog na ekranu telefona, bez
// preloma rasporeda. Sa SANKO_SHOTS=1 i --update-goldens snima ekrane u test/shots/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sanko/app.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/ui/admin/mobile_shell.dart';
import 'package:sanko/ui/admin/scope.dart';
import 'package:sanko/ui/role_screen.dart';
import 'package:sanko/ui/waiter/venue_code_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_backend.dart';

final _shots = Platform.environment['SANKO_SHOTS'] == '1';

Future<void> _loadFonts() async {
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

Future<void> _shot(String name) async {
  if (!_shots) return;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('shots/mobile_$name.png'),
  );
}

/// Lokal sa tri smjene danas: Amra sa manjkom, Bakir tačno, i Amrina otvorena smjena.
Future<Repository> _seed(Database db) async {
  var now = DateTime.now().copyWith(hour: 7, minute: 0);
  final repo = Repository(db, now: () => now);
  await repo.addWorker(name: 'Amra', pin: '1111');
  await repo.addWorker(name: 'Bakir', pin: '2222');
  await repo.seedDemoItems();

  final images = [
    for (final f in Directory('supabase/slike').listSync().whereType<File>())
      if (const ['.png', '.jpg'].contains(path.extension(f.path)))
        CatalogImage(
          id: 'slika-${path.basenameWithoutExtension(f.path)}',
          name: path.basenameWithoutExtension(f.path),
          bytes: await f.readAsBytes(),
        ),
  ];
  await repo.saveImages(images);
  for (final item in await repo.items()) {
    final image = images.where((i) => i.name == item.name).firstOrNull;
    final (min, par) = switch (item.name) {
      'KOLA' => (100, 144),
      'ĐUS' => (48, null),
      'RED BULL' => (24, 48),
      _ => (null, null),
    };
    await repo.updateItem(
      Item(
        id: item.id,
        name: item.name,
        kind: item.kind,
        price: item.price,
        initialQty: item.initialQty,
        imageId: image?.id,
        minQty: min,
        parQty: par,
      ),
    );
  }

  final ids = {for (final i in await repo.items()) i.name: i.id};
  final amra = (await repo.workerByPin('1111'))!;
  final bakir = (await repo.workerByPin('2222'))!;

  Future<void> count(String shiftId, Map<String, int> sold) async {
    final o = await repo.obracunForShift(shiftId);
    for (final l in o.lines) {
      final closing = l.kind == ItemKind.counter
          ? l.opening + (sold[l.name] ?? 0)
          : l.total - (sold[l.name] ?? 0);
      await repo.setClosingQty(shiftId, l.itemId, closing);
    }
  }

  final first = await repo.startShift(amra.id);
  await repo.setDraftReceiptQty(first.id, ids['KOLA']!, 24);
  await repo.closeDraftReceipt(first.id);
  await repo.addExpense(first.id, description: 'Konzum, mlijeko', amount: 300);
  await count(first.id, {
    'KAFA': 212,
    'KAPUCINO': 18,
    'KOLA': 13,
    'ĐUS': 9,
    'RED BULL': 4,
  });
  // KOLA: konobar je prebrojao više nego što je moglo biti.
  await repo.setClosingQty(first.id, ids['SPRITE']!, 34);
  final o1 = await repo.obracunForShift(first.id);
  now = now.copyWith(hour: 15, minute: 4);
  await repo.closeShift(
    first.id,
    handover: Handover(
      kitchen: 4500,
      cash: o1.sank + 4500 - o1.expenses - 7000 - 1000,
      card: 7000,
    ),
  );

  now = now.copyWith(hour: 15, minute: 10);
  final second = await repo.startShift(bakir.id);
  await repo.addExpense(second.id, description: 'Led', amount: 500);
  await count(second.id, {'KAFA': 180, 'TOČENO': 22, 'SARAJEVSKO': 9});
  final o2 = await repo.obracunForShift(second.id);
  now = now.copyWith(hour: 22, minute: 58);
  await repo.closeShift(
    second.id,
    handover: Handover(kitchen: 0, cash: o2.total, card: 0),
  );

  now = now.copyWith(hour: 23, minute: 2);
  await repo.startShift(amra.id);
  return repo;
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('gazda na telefonu vidi sve stranice bez preloma', (
    tester,
  ) async {
    late Database db;
    late Repository repo;
    await tester.runAsync(() async {
      db = await openTestDb(isolate: false);
      repo = await _seed(db);
    });
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 2;
    // Visok ekran, da snimak pokaže i ono ispod prvog ekrana; širina je telefona.
    tester.view.physicalSize = const Size(390, 1500) * 2;

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    // Lista stranice je lijena: daleki dio se iscrta tek kad se do njega pomjeri.
    Future<void> scrollTo(Finder f) async {
      final list = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .hitTestable();
      await tester.scrollUntilVisible(f, 400, scrollable: list.first);
      await settle();
    }

    // Tastatura telefona zauzme donji dio ekrana; dijalog se ne smije prelomiti.
    Future<void> withKeyboard() async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 330 * 2);
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.tap(f);
      await settle();
    }

    await tester.pumpWidget(
      SankoMaterialApp(
        builder: (context, child) => AdminScope(data: repo, child: child!),
        home: const MobileAdminShell(venueName: 'Centar'),
      ),
    );
    await settle();

    // Obračun: cijeli dan, pa jedna smjena.
    expect(find.text('Obračun'), findsWidgets);
    expect(find.textContaining('još nije zaključena'), findsOneWidget);
    await _shot('01_obracun_dan');
    await tap(find.textContaining('Smjena 1, Amra'));
    expect(find.text('Manjak 10,00 KM'), findsOneWidget);
    expect(find.text('SPRITE'), findsOneWidget);
    await _shot('02_obracun_smjena');

    await tap(find.text('Kuhinja i predaja'));
    await withKeyboard();
    expect(find.textContaining('manjak 10,00 KM'), findsOneWidget);
    await _shot('03_predaja_dijalog');
    await tap(find.text('Odustani'));

    await tap(find.text('Ispravi smjenu'));
    await withKeyboard();
    await _shot('04_ispravka_dijalog');
    await tap(find.text('Odustani'));

    await tap(find.textContaining('Smjena 3, Amra'));
    await tap(find.text('Zaključi smjenu').first);
    await withKeyboard();
    await _shot('05_zakljucenje_dijalog');
    await tap(find.text('Odustani'));

    // Izvještaj.
    await tap(find.text('Izvještaj'));
    await _shot('06_izvjestaj');
    await scrollTo(find.text('Po konobaru'));
    await scrollTo(find.text('Bakir'));
    await tap(find.text('Amra'));
    await _shot('07_izvjestaj_konobar');

    // Narudžba.
    await tap(find.text('Narudžba'));
    expect(find.text('Pošalji na Viber'), findsOneWidget);
    expect(find.text('KOLA'), findsOneWidget);
    await _shot('08_narudzba');

    // Artikli i dijalog artikla.
    await tap(find.text('Artikli'));
    expect(find.text('KAFA'), findsWidgets);
    await _shot('09_artikli');
    await tap(find.text('KOLA').first);
    expect(find.text('Izmjena artikla'), findsOneWidget);
    await withKeyboard();
    await _shot('10_artikal_dijalog');
    await tap(find.text('Odustani'));

    // Više: Prosjek, Radnici, Obavještenja.
    await tap(find.text('Više'));
    await _shot('11_vise');
    await tap(find.text('Prosjek'));
    expect(find.textContaining('Zadnjih 30 dana:'), findsOneWidget);
    await _shot('12_prosjek');
    await tap(find.byType(BackButton));
    await tap(find.text('Radnici'));
    expect(find.text('Bakir'), findsOneWidget);
    await _shot('13_radnici');
    await tap(find.text('Novi radnik'));
    await withKeyboard();
    await _shot('14_radnik_dijalog');
    await tap(find.text('Odustani'));
    await tap(find.byType(BackButton));
    await tap(find.text('Obavještenja'));
    await _shot('15_obavjestenja');
  });

  testWidgets('telefon pita ko ga koristi, a konobar može preći na gazdu', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    final picked = <PhoneRole>[];

    await tester.pumpWidget(
      SankoMaterialApp(home: RoleScreen(onPick: picked.add)),
    );
    await tester.pumpAndSettle();
    await _shot('00_uloga');
    await tester.tap(find.text('Gazda'));
    expect(picked, [PhoneRole.owner]);

    await tester.pumpWidget(
      PhoneRoleScope(
        switchTo: picked.add,
        child: const SankoMaterialApp(home: VenueCodeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gazda? Prijava e-mailom'));
    expect(picked, [PhoneRole.owner, PhoneRole.owner]);
  });
}
