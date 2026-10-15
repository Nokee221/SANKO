/// Cijelo stanje jedne smjene u obliku u kojem putuje između telefona i servera.
class RemoteShift {
  const RemoteShift({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.businessDate,
    required this.seq,
    required this.openedAt,
    required this.closedAt,
    required this.lines,
    required this.receipts,
    required this.expenses,
    this.kitchen,
    this.cash,
    this.card,
  });

  final String id;
  final String workerId;
  final String workerName;

  /// Dan smjene kao "yyyy-MM-dd".
  final String businessDate;
  final int seq;
  final DateTime openedAt;
  final DateTime? closedAt;
  final List<RemoteLine> lines;
  final List<RemoteReceipt> receipts;
  final List<RemoteExpense> expenses;

  /// Kuhinja i predaja novca, unesene pri zaključenju; null prije toga.
  final int? kitchen;
  final int? cash;
  final int? card;

  /// Red iz Supabasea sa ugniježđenim shift_lines, receipts(receipt_lines) i expenses.
  factory RemoteShift.fromJson(Map<String, dynamic> j) => RemoteShift(
    id: j['id'] as String,
    workerId: j['worker_id'] as String,
    workerName: j['worker_name'] as String,
    businessDate: j['business_date'] as String,
    seq: j['seq'] as int,
    openedAt: DateTime.parse(j['opened_at'] as String),
    closedAt: j['closed_at'] == null
        ? null
        : DateTime.parse(j['closed_at'] as String),
    lines: [
      for (final l in j['shift_lines'] as List)
        RemoteLine(
          itemId: l['item_id'] as String,
          name: l['item_name'] as String,
          kind: l['kind'] as String,
          price: l['price'] as int,
          sortOrder: l['sort_order'] as int,
          openingQty: l['opening_qty'] as int,
          closingQty: l['closing_qty'] as int?,
          imageId: l['image_id'] as String?,
        ),
    ],
    receipts: [
      for (final r in j['receipts'] as List)
        RemoteReceipt(
          id: r['id'] as String,
          createdAt: DateTime.parse(r['created_at'] as String),
          closedAt: r['closed_at'] == null
              ? null
              : DateTime.parse(r['closed_at'] as String),
          lines: {
            for (final l in r['receipt_lines'] as List)
              l['item_id'] as String: l['qty'] as int,
          },
        ),
    ],
    expenses: [
      for (final e in j['expenses'] as List)
        RemoteExpense(
          id: e['id'] as String,
          description: e['description'] as String,
          amount: e['amount'] as int,
          createdAt: DateTime.parse(e['created_at'] as String),
        ),
    ],
    kitchen: j['kitchen'] as int?,
    cash: j['cash'] as int?,
    card: j['card'] as int?,
  );

  /// Tijelo poziva sync_shift.
  Map<String, Object?> toPayload() => {
    'id': id,
    'closed_at': closedAt?.toUtc().toIso8601String(),
    'kitchen': kitchen,
    'cash': cash,
    'card': card,
    'counts': [
      for (final l in lines)
        if (l.closingQty != null)
          {'item_id': l.itemId, 'closing_qty': l.closingQty},
    ],
    'receipts': [
      for (final r in receipts)
        {
          'id': r.id,
          'created_at': r.createdAt.toUtc().toIso8601String(),
          'closed_at': r.closedAt?.toUtc().toIso8601String(),
          'lines': [
            for (final e in r.lines.entries) {'item_id': e.key, 'qty': e.value},
          ],
        },
    ],
    'expenses': [
      for (final e in expenses)
        {
          'id': e.id,
          'description': e.description,
          'amount': e.amount,
          'created_at': e.createdAt.toUtc().toIso8601String(),
        },
    ],
  };
}

class RemoteLine {
  const RemoteLine({
    required this.itemId,
    required this.name,
    required this.kind,
    required this.price,
    required this.sortOrder,
    required this.openingQty,
    required this.closingQty,
    this.imageId,
  });

  final String itemId;
  final String name;

  /// "stock" ili "counter".
  final String kind;
  final int price;
  final int sortOrder;
  final int openingQty;
  final int? closingQty;

  /// Slika artikla iz kataloga.
  final String? imageId;
}

class RemoteReceipt {
  const RemoteReceipt({
    required this.id,
    required this.createdAt,
    required this.closedAt,
    required this.lines,
  });

  final String id;
  final DateTime createdAt;
  final DateTime? closedAt;

  /// Količina po artiklu.
  final Map<String, int> lines;
}

class RemoteExpense {
  const RemoteExpense({
    required this.id,
    required this.description,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String description;
  final int amount;
  final DateTime createdAt;
}
