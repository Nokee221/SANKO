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
  const Obracun({required this.lines, required this.expenses});

  final List<ObracunLine> lines;

  /// Zbir rashoda u feninzima.
  final int expenses;

  bool get isComplete => lines.every((l) => l.closing != null);

  int get sank => lines.fold(0, (sum, l) => sum + (l.amount ?? 0));

  int get total => sank - expenses;

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
    return Obracun(
      lines: [for (final id in order) byItem[id]!],
      expenses: shifts.fold(0, (sum, s) => sum + s.expenses),
    );
  }
}
