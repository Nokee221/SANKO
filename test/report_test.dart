import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/domain/item_import.dart';
import 'package:sanko/domain/report.dart';
import 'package:sanko/domain/stats.dart';
import 'package:sanko/domain/xlsx_writer.dart';

ShiftSummary shift(
  int day,
  String worker, {
  int sank = 100000,
  int kitchen = 0,
  int expenses = 0,
  int? cash,
  int month = 10,
}) => ShiftSummary(
  shiftId: '$month-$day-$worker',
  businessDate: DateTime(2026, month, day),
  seq: 1,
  workerName: worker,
  sank: sank,
  kitchen: kitchen,
  expenses: expenses,
  cash: cash,
  card: cash == null ? null : 0,
);

StatLine line(String item, int consumed, {int price = 350, int day = 1}) =>
    StatLine(
      itemId: item,
      itemName: item,
      kind: ItemKind.stock,
      sortOrder: 0,
      businessDate: DateTime(2026, 10, day),
      shiftId: 's$day',
      seq: 1,
      workerName: 'Amra',
      consumed: consumed,
      received: 0,
      price: price,
    );

void main() {
  test('mjesečni pregled: promet, dani u sedmici i poređenje', () {
    final report = MonthReport(
      month: DateTime(2026, 10),
      shifts: [
        // 5.10.2026. je ponedjeljak; dvije smjene istog dana se sabiraju.
        shift(5, 'Amra', sank: 80000, kitchen: 5000),
        shift(5, 'Bakir', sank: 40000),
        shift(12, 'Amra', sank: 60000, expenses: 1000),
        shift(10, 'Bakir', sank: 90000),
      ],
      previous: [shift(20, 'Amra', sank: 200000, month: 9)],
      lines: const [],
    );
    expect(report.revenue, 275000);
    expect(report.kitchen, 5000);
    expect(report.days, 3);
    expect(report.change, closeTo(37.5, 0.001));
    // Ponedjeljci: 125.000 i 60.000, prosjek 92.500; subota 90.000.
    expect(report.weekdays[0], 92500);
    expect(report.weekdays[5], 90000);
    expect(report.weekdays[1], 0);
  });

  test('izvještaj po konobaru: manjak, višak i smjene bez predaje', () {
    final report = MonthReport(
      month: DateTime(2026, 10),
      shifts: [
        // Za predati 1.000,00 KM po smjeni.
        shift(1, 'Amra', cash: 99000),
        shift(2, 'Amra', cash: 100500),
        shift(3, 'Amra'),
        shift(4, 'Bakir', cash: 97000),
      ],
      previous: const [],
      lines: const [],
    );
    final workers = {for (final w in report.workers) w.name: w};
    expect(workers['Amra']!.shortShifts.length, 1);
    expect(workers['Amra']!.shortage, 1000);
    expect(workers['Amra']!.surplus, 500);
    expect(workers['Amra']!.withHandover, 2);
    expect(workers['Bakir']!.shortage, 3000);
    expect(report.difference, -1000 + 500 - 3000);
    // Višak ne poništava manjak.
    expect(report.shortage, 4000);
    expect(report.shortShifts.length, 2);
    expect(report.surplus, 500);
  });

  test('najprodavaniji artikli po prometu', () {
    final report = MonthReport(
      month: DateTime(2026, 10),
      shifts: [shift(1, 'Amra')],
      previous: const [],
      lines: [
        line('KOLA', 10),
        line('KOLA', 5, day: 2),
        line('KAFA', 40, price: 250),
        line('VODA', 0),
      ],
    );
    expect(report.items.map((i) => (i.name, i.qty, i.amount)), [
      ('KAFA', 40, 10000),
      ('KOLA', 15, 5250),
    ]);
  });

  test('narudžba: minimum, naručiti do i prosjek', () {
    Item item(String id, {int? min, int? par}) => Item(
      id: id,
      name: id,
      kind: ItemKind.stock,
      price: 350,
      minQty: min,
      parQty: par,
    );
    StockLevel level(String id, int stock) =>
        StockLevel(itemId: id, name: id, sortOrder: 0, stock: stock);
    // Pet dana istorije: FANTA se troši 10 dnevno.
    final history = ItemStats.compute([
      for (var d = 1; d <= 5; d++) ...[
        line('FANTA', 10, day: d),
        line('SPRITE', 10, day: d),
      ],
    ]);
    final lines = orderList(
      [
        item('KOLA', min: 24, par: 72),
        item('ĐUS', min: 12),
        item('VODA', min: 10),
        item('FANTA'),
        // Iznad minimuma, ali prema prosjeku nestaje za pola dana.
        item('SPRITE', min: 4, par: 40),
      ],
      [
        level('KOLA', 20),
        level('ĐUS', 12),
        level('VODA', 30),
        level('FANTA', 8),
        level('SPRITE', 5),
      ],
      history,
    );
    expect(lines.map((l) => (l.name, l.qty, l.byAverage)), [
      ('KOLA', 52, false),
      ('ĐUS', 12, false),
      ('FANTA', 62, true),
      ('SPRITE', 35, false),
    ]);
  });

  test('izvoz u Excel se čita nazad', () {
    final bytes = buildXlsx([
      const XlsxSheet(
        name: 'Artikli',
        header: ['Naziv artikla', 'Cijena', 'Stanje'],
        rows: [
          ['KOLA & FANTA <1>', XlsxMoney(350), 24],
          ['ČAJ', XlsxMoney(300), null],
        ],
      ),
    ]);
    final sheet = readXlsx(bytes).single;
    expect(sheet[0], ['Naziv artikla', 'Cijena', 'Stanje']);
    expect(sheet[1], ['KOLA & FANTA <1>', 3.5, 24]);
    expect(sheet[2], ['ČAJ', 3]);
    expect(itemsFromXlsx(bytes).map((i) => '${i.name} ${i.price}'), [
      'KOLA & FANTA <1> 350',
      'ČAJ 300',
    ]);
  });
}
