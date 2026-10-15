import '../data/models.dart';

/// Jedan red obračuna, kao red u knjizi šanka.
class ObracunLine {
  const ObracunLine({
    required this.itemId,
    required this.name,
    required this.kind,
    required this.price,
    required this.opening,
    required this.received,
    required this.closing,
    required this.consumed,
    required this.amount,
  });

  /// Red za jednu smjenu. Dok stanje nije uneseno, utrošeno i iznos su null.
  factory ObracunLine.forShift({
    required String itemId,
    required String name,
    required ItemKind kind,
    required int price,
    required int opening,
    required int received,
    required int? closing,
  }) {
    int? consumed;
    if (closing != null) {
      consumed = kind == ItemKind.stock
          ? opening + received - closing
          : closing - opening;
    }
    return ObracunLine(
      itemId: itemId,
      name: name,
      kind: kind,
      price: price,
      opening: opening,
      received: received,
      closing: closing,
      consumed: consumed,
      amount: consumed == null ? null : consumed * price,
    );
  }

  final String itemId;
  final String name;
  final ItemKind kind;
  final int price;

  /// Ostatak iz prethodne smjene, odnosno prethodno stanje brojača.
  final int opening;
  final int received;
  final int? closing;
  final int? consumed;
  final int? amount;

  int get total => kind == ItemKind.stock ? opening + received : opening;

  /// Prebrojano je više nego što je moglo biti: zaboravljen ulaz ili greška u brojanju.
  bool get hasAnomaly => consumed != null && consumed! < 0;
}

class Obracun {
  const Obracun({
    required this.lines,
    required this.expenses,
    this.kitchen = 0,
    this.cash,
    this.card,
    int? difference,
  }) : _difference = difference;

  final List<ObracunLine> lines;

  /// Zbir rashoda u feninzima.
  final int expenses;

  /// Iznos kuhinje koji konobar unese pri zaključenju; ulazi u za predati.
  final int kitchen;

  /// Predana gotovina i kartice; null dok smjena nije zaključena s predajom.
  final int? cash;
  final int? card;

  final int? _difference;

  bool get isComplete => lines.every((l) => l.closing != null);

  int get sank => lines.fold(0, (sum, l) => sum + (l.amount ?? 0));

  /// Za predati: šank i kuhinja, umanjeno za rashod.
  int get total => sank + kitchen - expenses;

  /// Predano ukupno; null bez predaje.
  int? get handedOver => cash == null ? null : cash! + (card ?? 0);

  /// Predano minus za predati: minus je manjak, plus višak; null bez predaje.
  int? get difference {
    if (_difference != null) return _difference;
    final handed = handedOver;
    return handed == null ? null : handed - total;
  }

  /// Obračun jedne smjene sa njenom kuhinjom i predajom.
  Obracun withHandover({required int kitchen, int? cash, int? card}) => Obracun(
    lines: lines,
    expenses: expenses,
    kitchen: kitchen,
    cash: cash,
    card: card,
  );

  /// Spaja smjene jednog dana (poredane po redu) u dnevni obračun.
  /// Početno stanje je iz prve smjene u kojoj se artikal pojavio, krajnje iz zadnje.
  /// Ako je zadnja smjena još otvorena, utrošeno i iznos pokrivaju samo zaključene.
  factory Obracun.forDay(List<Obracun> shifts) {
    final order = <String>[];
    final byItem = <String, ObracunLine>{};
    for (final shift in shifts) {
      for (final l in shift.lines) {
        final prev = byItem[l.itemId];
        if (prev == null) {
          order.add(l.itemId);
          byItem[l.itemId] = l;
          continue;
        }
        // Smjena koja je još otvorena ne ulazi u utrošeno i iznos dok se ne prebroji.
        int? sum(int? a, int? b) =>
            a == null && b == null ? null : (a ?? 0) + (b ?? 0);
        byItem[l.itemId] = ObracunLine(
          itemId: l.itemId,
          name: l.name,
          kind: l.kind,
          price: l.price,
          opening: prev.opening,
          received: prev.received + l.received,
          closing: l.closing,
          consumed: sum(prev.consumed, l.consumed),
          amount: sum(prev.amount, l.amount),
        );
      }
    }
    // Razlika dana je zbir razlika smjena koje imaju predaju; manjak jedne
    // ne smije nestati u zbiru sa smjenom bez predaje.
    final handed = shifts.where((s) => s.cash != null).toList();
    int sumOf(Iterable<int> values) => values.fold(0, (a, b) => a + b);
    return Obracun(
      lines: [for (final id in order) byItem[id]!],
      expenses: sumOf(shifts.map((s) => s.expenses)),
      kitchen: sumOf(shifts.map((s) => s.kitchen)),
      cash: handed.isEmpty ? null : sumOf(handed.map((s) => s.cash!)),
      card: handed.isEmpty ? null : sumOf(handed.map((s) => s.card ?? 0)),
      difference: handed.isEmpty
          ? null
          : sumOf(handed.map((s) => s.difference!)),
    );
  }
}
