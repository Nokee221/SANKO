import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/domain/stats.dart';

StatLine line(
  String item,
  int day,
  int seq,
  int consumed, {
  int received = 0,
}) => StatLine(
  itemId: item,
  itemName: item.toUpperCase(),
  kind: ItemKind.stock,
  sortOrder: item == 'breskva' ? 1 : 2,
  businessDate: DateTime(2026, 10, day),
  shiftId: 'smjena-$day-$seq',
  seq: seq,
  workerName: 'Kenan',
  consumed: consumed,
  received: received,
);

void main() {
  test('prosjek po danu, po smjeni i ulaz po danu', () {
    final stats = ItemStats.compute([
      line('breskva', 1, 1, 3),
      line('breskva', 1, 2, 2, received: 24),
      line('breskva', 2, 1, 5),
      line('kola', 1, 1, 10),
    ]);
    expect(stats.days, 2);
    expect(stats.shifts, 3);
    final b = stats.item('breskva')!;
    expect(b.consumed, 10);
    expect(b.perDay, 5);
    expect(b.perShift, 10 / 3);
    expect(b.maxShift, 5);
    expect(b.receivedPerDay, 12);
    expect(stats.items.map((i) => i.name), ['BRESKVA', 'KOLA']);
  });

  test(
    'neuobičajeno veliko i negativno utrošeno se označava, najnovije prvo',
    () {
      final stats = ItemStats.compute([
        line('breskva', 1, 1, 5),
        line('breskva', 2, 1, 4),
        line('breskva', 3, 1, 6),
        line('breskva', 4, 1, 5),
        line('breskva', 5, 1, 20),
        line('breskva', 6, 1, -3),
      ]);
      expect(stats.anomalies.map((a) => a.line.consumed), [-3, 20]);
      // Smjena sa 20 se poredi sa ostalima: (5 + 4 + 6 + 5 - 3) / 5.
      expect(stats.anomalies.last.expected, closeTo(3.4, 0.001));
    },
  );

  test('bez dovoljno istorije nema uzbune', () {
    final stats = ItemStats.compute([
      line('breskva', 1, 1, 1),
      line('breskva', 2, 1, 1),
      line('breskva', 3, 1, 30),
    ]);
    expect(stats.anomalies, isEmpty);
  });

  test('mala odstupanja kod artikala koji se malo prodaju nisu uzbuna', () {
    expect(isUnusual(3, 1), isFalse, reason: 'samo 2 više od prosjeka');
    expect(isUnusual(4, 1), isTrue);
    expect(isUnusual(12, 5), isFalse, reason: 'manje od 2,5 puta');
    expect(isUnusual(13, 5), isTrue);
  });

  test('niska zaliha prema prosječnoj dnevnoj potrošnji', () {
    final stats = ItemStats.compute([
      for (var day = 1; day <= 5; day++) ...[
        line('breskva', day, 1, 5),
        line('kola', day, 1, 10),
      ],
    ]);
    StockLevel level(String id, int stock) => StockLevel(
      itemId: id,
      name: id.toUpperCase(),
      sortOrder: 1,
      stock: stock,
    );
    final forecasts = forecastStock([
      level('kola', 50),
      level('breskva', 6),
      level('fanta', 0),
      level('voda', 12),
    ], stats);

    expect(forecasts.map((f) => f.level.itemId), [
      'fanta',
      'breskva',
      'kola',
      'voda',
    ]);
    expect(forecasts.where((f) => f.isLow).map((f) => f.level.itemId), [
      'fanta',
      'breskva',
    ]);
    expect(forecasts[1].daysLeft, closeTo(1.2, 0.001));
    expect(forecasts[2].daysLeft, 5);
    expect(forecasts[3].daysLeft, isNull, reason: 'voda se ne troši');
  });

  test('bez dovoljno istorije upozorava samo kad zalihe nema', () {
    final stats = ItemStats.compute([line('breskva', 1, 1, 5)]);
    final forecasts = forecastStock([
      const StockLevel(
        itemId: 'breskva',
        name: 'BRESKVA',
        sortOrder: 1,
        stock: 2,
      ),
      const StockLevel(itemId: 'kola', name: 'KOLA', sortOrder: 2, stock: 0),
    ], stats);
    expect(forecasts.where((f) => f.isLow).map((f) => f.level.itemId), [
      'kola',
    ]);
  });
}
