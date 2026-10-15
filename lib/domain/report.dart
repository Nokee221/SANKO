import '../data/models.dart';
import 'stats.dart';

/// Zbir jedne zaključene smjene: šank, kuhinja, rashod, predaja i anomalije.
class ShiftSummary {
  const ShiftSummary({
    required this.shiftId,
    required this.businessDate,
    required this.seq,
    required this.workerName,
    required this.sank,
    required this.expenses,
    this.kitchen,
    this.cash,
    this.card,
    this.closedByAdmin = false,
    this.anomalies = const [],
  });

  /// Red iz admin_shift_summaries.
  factory ShiftSummary.fromJson(Map<String, dynamic> j) => ShiftSummary(
    shiftId: j['shift_id'] as String,
    businessDate: DateTime.parse(j['business_date'] as String),
    seq: j['seq'] as int,
    workerName: j['worker_name'] as String,
    sank: (j['sank'] as num).toInt(),
    expenses: (j['expenses'] as num).toInt(),
    kitchen: j['kitchen'] as int?,
    cash: j['cash'] as int?,
    card: j['card'] as int?,
    closedByAdmin: j['closed_by_admin'] as bool? ?? false,
    anomalies: [
      for (final a in j['anomalies'] as List? ?? const [])
        a['item_name'] as String,
    ],
  );

  final String shiftId;
  final DateTime businessDate;
  final int seq;
  final String workerName;
  final int sank;
  final int expenses;

  /// null kod smjena zaključenih prije uvođenja kuhinje i predaje.
  final int? kitchen;
  final int? cash;
  final int? card;
  final bool closedByAdmin;

  /// Artikli kod kojih je prebrojano više nego što je moglo biti.
  final List<String> anomalies;

  /// Promet: šank i kuhinja.
  int get revenue => sank + (kitchen ?? 0);

  /// Za predati.
  int get total => revenue - expenses;

  int? get handedOver => cash == null ? null : cash! + (card ?? 0);

  /// Predano minus za predati: minus je manjak; null bez predaje.
  int? get difference => handedOver == null ? null : handedOver! - total;
}

/// Jedan konobar u periodu: promet, manjkovi i anomalije.
class WorkerReport {
  const WorkerReport({
    required this.name,
    required this.shifts,
    required this.anomalies,
  });

  final String name;

  /// Njegove smjene u periodu, najstarije prve.
  final List<ShiftSummary> shifts;

  /// Sumnjiva brojanja u njegovim smjenama: prebrojano više nego moguće,
  /// ili potrošnja mnogo veća od uobičajene.
  final int anomalies;

  int get revenue => shifts.fold(0, (sum, s) => sum + s.revenue);

  /// Smjene sa manjkom.
  List<ShiftSummary> get shortShifts => [
    for (final s in shifts)
      if ((s.difference ?? 0) < 0) s,
  ];

  /// Zbir manjkova, kao pozitivan broj.
  int get shortage => shortShifts.fold(0, (sum, s) => sum - s.difference!);

  /// Zbir viškova.
  int get surplus => shifts.fold(
    0,
    (sum, s) => (s.difference ?? 0) > 0 ? sum + s.difference! : sum,
  );

  /// Smjene sa unesenom predajom.
  int get withHandover => shifts.where((s) => s.difference != null).length;
}

/// Promet jednog artikla u periodu.
class ItemRevenue {
  const ItemRevenue({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.amount,
  });

  final String itemId;
  final String name;
  final int qty;
  final int amount;
}

/// Pregled jednog mjeseca, sa poređenjem sa prethodnim.
class MonthReport {
  MonthReport({
    required this.month,
    required this.shifts,
    required this.previous,
    required this.lines,
  });

  /// Prvi dan mjeseca.
  final DateTime month;

  /// Zaključene smjene mjeseca, najstarije prve.
  final List<ShiftSummary> shifts;

  /// Zaključene smjene prethodnog mjeseca.
  final List<ShiftSummary> previous;

  /// Utrošeno po artiklu u smjenama mjeseca.
  final List<StatLine> lines;

  static int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

  int get revenue => _sum(shifts.map((s) => s.revenue));
  int get sank => _sum(shifts.map((s) => s.sank));
  int get kitchen => _sum(shifts.map((s) => s.kitchen ?? 0));
  int get expenses => _sum(shifts.map((s) => s.expenses));
  int get previousRevenue => _sum(previous.map((s) => s.revenue));

  /// Zbir razlika predaje; minus je ukupni manjak.
  int get difference => _sum(shifts.map((s) => s.difference ?? 0));

  /// Smjene sa manjkom u predaji.
  List<ShiftSummary> get shortShifts => [
    for (final s in shifts)
      if ((s.difference ?? 0) < 0) s,
  ];

  /// Zbir manjkova, kao pozitivan broj; višak ga ne poništava.
  int get shortage => _sum(shortShifts.map((s) => -s.difference!));

  /// Zbir viškova.
  int get surplus => _sum([
    for (final s in shifts)
      if ((s.difference ?? 0) > 0) s.difference!,
  ]);

  /// Dani sa bar jednom zaključenom smjenom.
  int get days => {for (final s in shifts) s.businessDate}.length;

  double get perDay => days == 0 ? 0 : revenue / days;

  /// Promjena prometa prema prethodnom mjesecu, u procentima; null bez poređenja.
  double? get change => previousRevenue == 0
      ? null
      : (revenue - previousRevenue) * 100 / previousRevenue;

  /// Promet po danu u mjesecu.
  Map<DateTime, int> get daily {
    final days = <DateTime, int>{};
    for (final s in shifts) {
      days.update(
        s.businessDate,
        (v) => v + s.revenue,
        ifAbsent: () => s.revenue,
      );
    }
    return days;
  }

  /// Prosječan promet po danu u sedmici, od ponedjeljka; samo dani kad se radilo.
  List<double> get weekdays {
    final totals = List.filled(7, 0);
    final counts = List.filled(7, 0);
    for (final MapEntry(key: day, value: amount) in daily.entries) {
      totals[day.weekday - 1] += amount;
      counts[day.weekday - 1]++;
    }
    return [
      for (var i = 0; i < 7; i++) counts[i] == 0 ? 0 : totals[i] / counts[i],
    ];
  }

  /// Artikli po prometu, najprodavaniji prvi.
  List<ItemRevenue> get items {
    final byItem = <String, ItemRevenue>{};
    for (final l in lines) {
      final prev = byItem[l.itemId];
      byItem[l.itemId] = ItemRevenue(
        itemId: l.itemId,
        name: l.itemName,
        qty: (prev?.qty ?? 0) + l.consumed,
        amount: (prev?.amount ?? 0) + l.consumed * l.price,
      );
    }
    return byItem.values.where((i) => i.qty > 0).toList()..sort(
      (a, b) => b.amount != a.amount
          ? b.amount.compareTo(a.amount)
          : b.qty.compareTo(a.qty),
    );
  }

  /// Konobari po prometu.
  List<WorkerReport> get workers {
    final byWorker = <String, List<ShiftSummary>>{};
    for (final s in shifts) {
      byWorker.putIfAbsent(s.workerName, () => []).add(s);
    }
    final suspicious = <String, int>{};
    for (final a in ItemStats.compute(lines).anomalies) {
      suspicious.update(a.line.workerName, (v) => v + 1, ifAbsent: () => 1);
    }
    return [
      for (final MapEntry(key: name, value: list) in byWorker.entries)
        WorkerReport(
          name: name,
          shifts: list,
          anomalies: suspicious[name] ?? 0,
        ),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  }
}

/// Jedan red narudžbe.
class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    required this.stock,
    required this.qty,
    this.minQty,
    this.byAverage = false,
  });

  final String itemId;
  final String name;
  final int stock;

  /// Predložena količina za naručiti.
  final int qty;
  final int? minQty;

  /// Artikal nema minimum; ide na listu jer prema prosjeku uskoro nestaje.
  final bool byAverage;
}

/// Za koliko dana se naručuje artikal bez minimuma, prema prosječnoj potrošnji.
const orderDays = 7;

/// Lista za narudžbu: artikli čija je zaliha pala na minimum ili prema prosjeku ističe
/// za manje od [lowStockDays] dana (isto kao upozorenje na obračunu). Artikal sa
/// minimumom se naručuje do količine "naručiti do" (bez nje do dvostrukog minimuma),
/// a artikal bez minimuma za [orderDays] dana. Redoslijed je kao u listi artikala.
List<OrderLine> orderList(
  List<Item> items,
  List<StockLevel> stock,
  ItemStats history,
) {
  final levels = {for (final l in stock) l.itemId: l.stock};
  final enough = history.days >= minHistory;
  final lines = <OrderLine>[];
  for (final item in items) {
    final level = levels[item.id];
    if (level == null || item.kind != ItemKind.stock) continue;
    final min = item.minQty;
    final perDay = history.item(item.id)?.perDay ?? 0;
    // Prema prosjeku nestaje za manje od dva dana, kao u upozorenju na obračunu.
    final runningOut = enough && perDay > 0 && level / perDay < lowStockDays;
    if (min != null) {
      if (level > min && !runningOut) continue;
      final target = item.parQty ?? min * 2;
      lines.add(
        OrderLine(
          itemId: item.id,
          name: item.name,
          stock: level,
          minQty: min,
          // Bar jedan komad, i kad je "naručiti do" postavljeno nisko.
          qty: target - level > 0 ? target - level : 1,
        ),
      );
      continue;
    }
    if (!runningOut) continue;
    final need = (perDay * orderDays).ceil() - level;
    if (need <= 0) continue;
    lines.add(
      OrderLine(
        itemId: item.id,
        name: item.name,
        stock: level,
        qty: need,
        byAverage: true,
      ),
    );
  }
  return lines;
}
