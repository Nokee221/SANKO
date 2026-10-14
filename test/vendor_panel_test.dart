import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/admin_app.dart';
import 'package:sanko/app.dart';
import 'package:sanko/data/errors.dart';
import 'package:sanko/ui/format.dart';
import 'package:sanko/ui/vendor/vendor_panel.dart';
import 'package:sanko/vendor/vendor_api.dart';

final _shots = Platform.environment['SANKO_SHOTS'] == '1';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Server prodavca u memoriji.
class FakeVendorApi extends VendorApi {
  int price = 2500;
  final venues = <VendorVenue>[];
  final paymentsList = <VendorPayment>[];
  int created = 0;

  void addVenue_(String id, String org, String name, int daysLeft) =>
      venues.add(
        VendorVenue(
          id: id,
          orgId: 'org-$id',
          orgName: org,
          name: name,
          code: 'KOD${id.toUpperCase().padLeft(3, 'X')}',
          paidUntil: _today().add(Duration(days: daysLeft)),
          ownerEmails: ['gazda@$id.ba'],
          workers: 3,
          lastShiftAt: daysLeft < 0 ? null : DateTime.now(),
          shifts30: daysLeft < 0 ? 0 : 41,
        ),
      );

  VendorVenue _replace(String id, DateTime paidUntil) {
    final i = venues.indexWhere((v) => v.id == id);
    final v = venues[i];
    venues[i] = VendorVenue(
      id: v.id,
      orgId: v.orgId,
      orgName: v.orgName,
      name: v.name,
      code: v.code,
      paidUntil: paidUntil,
      ownerEmails: v.ownerEmails,
      workers: v.workers,
      lastShiftAt: v.lastShiftAt,
      shifts30: v.shifts30,
    );
    return venues[i];
  }

  @override
  Future<VendorOverview> overview() async =>
      VendorOverview(monthlyPrice: price, venues: List.of(venues));

  @override
  Future<List<VendorPayment>> payments() async => List.of(paymentsList);

  @override
  Future<DateTime> extend(
    String venueId,
    int months,
    int amount, {
    String? note,
  }) async {
    final v = venues.firstWhere((v) => v.id == venueId);
    final base = v.paidUntil.isBefore(_today()) ? _today() : v.paidUntil;
    final until = DateTime(base.year, base.month + months, base.day);
    _replace(venueId, until);
    paymentsList.insert(
      0,
      VendorPayment(
        orgName: v.orgName,
        venueName: v.name,
        amount: amount,
        months: months,
        paidUntilAfter: until,
        note: note,
        createdAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return until;
  }

  @override
  Future<void> setPaidUntil(
    String venueId,
    DateTime date, {
    String? note,
  }) async {
    _replace(venueId, date);
    notifyListeners();
  }

  @override
  Future<String> addVenue(String orgId, String name, DateTime paidUntil) async {
    notifyListeners();
    return 'NOVI01';
  }

  @override
  Future<String> createCustomer({
    required String orgName,
    required String venueName,
    required String email,
    required String password,
    required DateTime paidUntil,
    required int amount,
    String? note,
  }) async {
    if (!email.contains('@')) {
      throw SankoException('Unesite ispravan e-mail gazde.');
    }
    created++;
    venues.add(
      VendorVenue(
        id: 'novi',
        orgId: 'org-novi',
        orgName: orgName,
        name: venueName,
        code: 'MOST42',
        paidUntil: paidUntil,
        ownerEmails: [email],
        workers: 0,
        lastShiftAt: null,
        shifts30: 0,
      ),
    );
    notifyListeners();
    return 'MOST42';
  }

  @override
  Future<void> setPrice(int value) async {
    price = value;
    notifyListeners();
  }
}

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

void main() {
  setUpAll(_loadFonts);

  late FakeVendorApi api;

  Future<void> pump(WidgetTester tester) async {
    api = FakeVendorApi()
      ..addVenue_('a', 'Korzo', 'Centar', 40)
      ..addVenue_('b', 'Kafe Most', 'Most', 3)
      ..addVenue_('c', 'Bar Sunce', 'Obala', -5);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SankoMaterialApp(
        // Isto postavljanje kao u pravoj aplikaciji, da dijalozi vide vezu sa serverom.
        builder: (context, child) => withAdminScopes(child!, vendorApi: api),
        home: const VendorPanel(),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/logo.png'),
        tester.element(find.byType(VendorPanel)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(String name) async {
    if (!_shots) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('shots/$name.png'),
    );
  }

  testWidgets('lista kafića sa stanjem pretplate i filterima', (tester) async {
    await pump(tester);
    expect(find.textContaining('Aktivan do'), findsOneWidget);
    expect(find.text('Ističe za 3 dana'), findsOneWidget);
    expect(find.textContaining('Istekao'), findsOneWidget);
    expect(
      find.textContaining('aktivnih 2, mjesečno oko 50,00 KM'),
      findsOneWidget,
    );
    expect(find.text('Još nije radio'), findsOneWidget);
    await shot('20_prodavac_kafici');

    await tester.tap(find.text('Istekli (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bar Sunce'), findsOneWidget);
    expect(find.textContaining('Korzo'), findsNothing);

    await tester.tap(find.text('Svi (3)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'most');
    await tester.pumpAndSettle();
    expect(find.textContaining('Kafe Most'), findsOneWidget);
    expect(find.textContaining('Korzo'), findsNothing);
  });

  testWidgets(
    'produženje istekle pretplate se računa od danas i zapisuje uplatu',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Istekli (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Produži'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 mjeseca'));
      await tester.pumpAndSettle();
      final until = DateTime(_today().year, _today().month + 3, _today().day);
      expect(find.text('Novo: plaćeno do ${fmtDate(until)}'), findsOneWidget);
      expect(find.text('75,00'), findsOneWidget);
      await shot('21_prodavac_produzenje');
      await tester.tap(find.widgetWithText(FilledButton, 'Produži').last);
      await tester.pumpAndSettle();

      expect(api.paymentsList.single.amount, 7500);
      expect(api.paymentsList.single.months, 3);
      expect(find.textContaining('Istekli (0)'), findsOneWidget);
    },
  );

  testWidgets('novi kafić dobija nalog gazde i kod za telefone', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Novi kafić'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Naziv firme'),
      'Kafe Dva',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Naziv lokala'),
      'Most',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail gazde'),
      'novi@kafic.ba',
    );
    final password = tester
        .widget<TextField>(find.widgetWithText(TextField, 'Privremena lozinka'))
        .controller!
        .text;
    expect(password.length, 10);
    await tester.tap(find.text('Otvori kafić'));
    await tester.pumpAndSettle();

    expect(find.text('Kafić je otvoren'), findsOneWidget);
    expect(
      find.textContaining('Kod lokala za telefone konobara: MOST42'),
      findsOneWidget,
    );
    expect(find.textContaining(password), findsOneWidget);
    await shot('22_prodavac_novi_kafic');
    await tester.tap(find.text('Gotovo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kafe Dva, Most'), findsOneWidget);
  });

  testWidgets('uplate: zbirovi i promjena cijene', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Produži').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Produži').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Uplate'));
    await tester.pumpAndSettle();
    expect(find.text('25,00 KM'), findsNWidgets(3));
    await shot('23_prodavac_uplate');

    await tester.tap(find.textContaining('Cijena: 25,00 KM'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '30');
    await tester.tap(find.text('Sačuvaj'));
    await tester.pumpAndSettle();
    expect(api.price, 3000);
    expect(find.textContaining('Cijena: 30,00 KM'), findsOneWidget);
  });
}
