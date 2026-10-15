import '../data/models.dart';

/// Utrošeno i primljeno jednog artikla u jednoj zaključenoj smjeni.
class StatLine {
  const StatLine({
    required this.itemId,
    required this.itemName,
    required this.kind,
    required this.sortOrder,
    required this.businessDate,
    required this.shiftId,
    required this.seq,
    required this.workerName,
    required this.consumed,
    required this.received,
    this.price = 0,
  });

  /// Red iz admin_stat_lines.
  factory StatLine.fromJson(Map<String, dynamic> j) => StatLine(
    itemId: j['item_id'] as String,
    itemName: j['item_name'] as String,
    kind: ItemKind.values.byName(j['kind'] as String),
    sortOrder: j['sort_order'] as int,
    businessDate: DateTime.parse(j['business_date'] as String),
    shiftId: j['shift_id'] as String,
    seq: j['seq'] as int,
    workerName: j['worker_name'] as String,
    consumed: j['consumed'] as int,
    received: j['received'] as int,
    // Starija baza ne vraća cijenu; tada promet po artiklu nije poznat.
    price: j['price'] as int? ?? 0,
  );

  final String itemId;
  final String itemName;
  final ItemKind kind;
  final int sortOrder;
  final DateTime businessDate;
  final String shiftId;
  final int seq;
  final String workerName;
  final int consumed;
  final int received;

  /// Cijena u smjeni, u feninzima.
  final int price;
}

/// Koliko smjena istorije treba prije nego što se prosjek uzme kao mjerilo.
const minHistory = 3;

/// Neuobičajeno velika potrošnja: bar 2,5 puta više od prosjeka i bar 3 komada više.
/// Druga granica sprječava uzbunu za artikle koji se prodaju po jedan-dva.
bool isUnusual(int consumed, double average) =>
    consumed >= average * 2.5 && consumed - average >= 3;

class ItemAverage {
  const ItemAverage({
    required this.itemId,
    required this.name,
    required this.kind,
    required this.sortOrder,
    required this.shifts,
    required this.consumed,
    required this.received,
    required this.maxShift,
    required this.perDay,
    required this.perShift,
    required this.receivedPerDay,
  });

  final String itemId;
  final String name;
  final ItemKind kind;
  final int sortOrder;

  /// Broj zaključenih smjena u kojima je artikal bio.
  final int shifts;
  final int consumed;
  final int received;
  final int maxShift;
  final double perDay;
  final double perShift;
  final double receivedPerDay;
}

/// Brojanje koje je vjerovatno pogrešno: utrošeno je mnogo veće od uobičajenog,
/// ili negativno (prebrojano više nego što je moglo biti).
class CountAnomaly {
  const CountAnomaly({required this.line, required this.expected});

  final StatLine line;

  /// Prosjek po smjeni u ostalim smjenama perioda.
  final double expected;
}

class ItemStats {
  const ItemStats({
    required this.days,
    required this.shifts,
    required this.items,
    required this.anomalies,
  });

  /// Broj dana sa bar jednom zaključenom smjenom.
  final int days;
  final int shifts;
  final List<ItemAverage> items;

  /// Najnovije prvo.
  final List<CountAnomaly> anomalies;

  ItemAverage? item(String itemId) =>
      items.where((i) => i.itemId == itemId).firstOrNull;

  factory ItemStats.compute(List<StatLine> lines) {
    final days = {for (final l in lines) l.businessDate}.length;
    final shifts = {for (final l in lines) l.shiftId}.length;
    final byItem = <String, List<StatLine>>{};
    for (final l in lines) {
      byItem.putIfAbsent(l.itemId, () => []).add(l);
    }

    final items = <ItemAverage>[];
    final anomalies = <CountAnomaly>[];
    for (final group in byItem.values) {
      final latest = group.last;
      final consumed = group.fold(0, (sum, l) => sum + l.consumed);
      final received = group.fold(0, (sum, l) => sum + l.received);
      items.add(
        ItemAverage(
          itemId: latest.itemId,
          name: latest.itemName,
          kind: latest.kind,
          sortOrder: latest.sortOrder,
          shifts: group.length,
          consumed: consumed,
          received: received,
          maxShift: group
              .map((l) => l.consumed)
              .reduce((a, b) => a > b ? a : b),
          perDay: consumed / days,
          perShift: consumed / group.length,
          receivedPerDay: received / days,
        ),
      );
      if (group.length <= minHistory) continue;
      for (final l in group) {
        // Smjena se poredi sa ostalima, da sama ne podigne prosjek s kojim se poredi.
        final expected = (consumed - l.consumed) / (group.length - 1);
        if (l.consumed < 0 || isUnusual(l.consumed, expected)) {
          anomalies.add(CountAnomaly(line: l, expected: expected));
        }
      }
    }
    items.sort(
      (a, b) => a.sortOrder != b.sortOrder
          ? a.sortOrder.compareTo(b.sortOrder)
          : a.name.compareTo(b.name),
    );
    anomalies.sort((a, b) {
      final byDate = b.line.businessDate.compareTo(a.line.businessDate);
      return byDate != 0 ? byDate : b.line.seq.compareTo(a.line.seq);
    });
    return ItemStats(
      days: days,
      shifts: shifts,
      items: items,
      anomalies: anomalies,
    );
  }
}

/// Trenutna zaliha artikla: ostatak sa zadnjeg brojanja plus kasnije zaključeni ulazi.
class StockLevel {
  const StockLevel({
    required this.itemId,
    required this.name,
    required this.sortOrder,
    required this.stock,
  });

  factory StockLevel.fromJson(Map<String, dynamic> j) => StockLevel(
    itemId: j['item_id'] as String,
    name: j['name'] as String,
    sortOrder: j['sort_order'] as int,
    stock: j['stock'] as int,
  );

  final String itemId;
  final String name;
  final int sortOrder;
  final int stock;
}

/// Zaliha je niska kad prema prosječnoj potrošnji ne bi potrajala ni ovoliko dana.
const lowStockDays = 2.0;

class StockForecast {
  const StockForecast({
    required this.level,
    required this.perDay,
    required this.isLow,
  });

  final StockLevel level;

  /// Prosječna dnevna potrošnja; 0 kad je nema u istoriji.
  final double perDay;
  final bool isLow;

  /// Za koliko dana je zaliha dovoljna: 0 kad je nema, null kad se artikal ne troši.
  double? get daysLeft {
    if (level.stock <= 0) return 0;
    return perDay > 0 ? level.stock / perDay : null;
  }
}

/// Procjena zalihe za sve artikle; najkritičniji prvi. Artikal sa minimumom
/// iz [minimums] je nizak čim zaliha padne na minimum.
List<StockForecast> forecastStock(
  List<StockLevel> levels,
  ItemStats stats, {
  Map<String, int> minimums = const {},
}) {
  final enough = stats.days >= minHistory;
  final forecasts = [
    for (final level in levels)
      () {
        final perDay = stats.item(level.itemId)?.perDay ?? 0;
        final daysLeft = perDay > 0 ? level.stock / perDay : null;
        return StockForecast(
          level: level,
          perDay: perDay,
          isLow:
              level.stock <= 0 ||
              level.stock <= (minimums[level.itemId] ?? -1) ||
              (enough && daysLeft != null && daysLeft < lowStockDays),
        );
      }(),
  ];
  forecasts.sort((a, b) {
    if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
    final da = a.daysLeft ?? double.infinity;
    final db = b.daysLeft ?? double.infinity;
    if (da != db) return da.compareTo(db);
    return a.level.sortOrder.compareTo(b.level.sortOrder);
  });
  return forecasts;
}
