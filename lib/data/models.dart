import 'dart:typed_data';

/// Vrsta artikla: zaliha se broji na komad, brojač je stanje s aparata koje samo raste.
enum ItemKind { stock, counter }

/// Konobar kuca narudžbe i vodi knjigu šanka; šank samo prima narudžbe.
enum WorkerRole {
  konobar('Konobar'),
  sank('Šank');

  const WorkerRole(this.label);

  final String label;

  static WorkerRole parse(Object? value) => value == 'sank' ? sank : konobar;
}

class Worker {
  const Worker({
    required this.id,
    required this.name,
    this.pin = '',
    this.active = true,
    this.role = WorkerRole.konobar,
  });

  final String id;
  final String name;

  /// Poznat samo na telefonu radnika; u admin panelu je prazan.
  final String pin;
  final bool active;
  final WorkerRole role;

  factory Worker.fromRow(Map<String, Object?> r) => Worker(
    id: r['id'] as String,
    name: r['name'] as String,
    pin: r['pin'] as String,
    active: r['active'] == 1,
    role: WorkerRole.parse(r['role']),
  );
}

class Item {
  const Item({
    required this.id,
    required this.name,
    required this.kind,
    required this.price,
    this.initialQty = 0,
    this.sortOrder = 0,
    this.active = true,
    this.imageId,
    this.minQty,
    this.parQty,
  });

  final String id;
  final String name;
  final ItemKind kind;

  /// Zaliha na kojoj artikal ide na listu za narudžbu; null znači da se ne prati.
  final int? minQty;

  /// Do koliko se naručuje; bez nje se naručuje do dvostrukog minimuma.
  final int? parQty;

  /// Slika iz kataloga; null znači da artikal nema sliku.
  final String? imageId;

  /// Cijena u feninzima.
  final int price;
  final int initialQty;
  final int sortOrder;
  final bool active;

  /// Red iz Supabasea.
  factory Item.fromRemote(Map<String, dynamic> r) => Item(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: ItemKind.values.byName(r['kind'] as String),
    price: r['price'] as int,
    initialQty: r['initial_qty'] as int,
    sortOrder: r['sort_order'] as int,
    imageId: r['image_id'] as String?,
    active: r['active'] as bool,
    minQty: r['min_qty'] as int?,
    parQty: r['par_qty'] as int?,
  );

  factory Item.fromRow(Map<String, Object?> r) => Item(
    id: r['id'] as String,
    name: r['name'] as String,
    kind: ItemKind.values.byName(r['kind'] as String),
    price: r['price'] as int,
    initialQty: r['initial_qty'] as int,
    sortOrder: r['sort_order'] as int,
    imageId: r['image_id'] as String?,
    active: r['active'] == 1,
    minQty: r['min_qty'] as int?,
    parQty: r['par_qty'] as int?,
  );
}

class Shift {
  const Shift({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.businessDate,
    required this.seq,
    required this.openedAt,
    this.closedAt,
    this.closedByAdmin = false,
  });

  final String id;
  final String workerId;
  final String workerName;

  /// Dan kojem smjena pripada (dan otvaranja), bez vremena.
  final DateTime businessDate;

  /// Redni broj smjene u danu, od 1.
  final int seq;
  final DateTime openedAt;
  final DateTime? closedAt;

  /// Smjenu je iz admin panela zaključio gazda, a ne konobar.
  final bool closedByAdmin;

  bool get isClosed => closedAt != null;

  /// Red iz Supabasea.
  factory Shift.fromRemote(Map<String, dynamic> r) => Shift(
    id: r['id'] as String,
    workerId: r['worker_id'] as String,
    workerName: r['worker_name'] as String,
    businessDate: DateTime.parse(r['business_date'] as String),
    seq: r['seq'] as int,
    openedAt: DateTime.parse(r['opened_at'] as String).toLocal(),
    closedAt: r['closed_at'] == null
        ? null
        : DateTime.parse(r['closed_at'] as String).toLocal(),
    closedByAdmin: r['closed_by_admin'] as bool? ?? false,
  );

  factory Shift.fromRow(Map<String, Object?> r) => Shift(
    id: r['id'] as String,
    workerId: r['worker_id'] as String,
    workerName: r['worker_name'] as String,
    businessDate: DateTime.parse(r['business_date'] as String),
    seq: r['seq'] as int,
    openedAt: DateTime.fromMillisecondsSinceEpoch(r['opened_at'] as int),
    closedAt: r['closed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['closed_at'] as int),
  );
}

class Expense {
  const Expense({
    required this.id,
    required this.shiftId,
    required this.description,
    required this.amount,
    required this.createdAt,
  });

  final String id;
  final String shiftId;
  final String description;

  /// Iznos u feninzima.
  final int amount;
  final DateTime createdAt;

  /// Red iz Supabasea.
  factory Expense.fromRemote(Map<String, dynamic> r) => Expense(
    id: r['id'] as String,
    shiftId: r['shift_id'] as String,
    description: r['description'] as String,
    amount: r['amount'] as int,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
  );

  factory Expense.fromRow(Map<String, Object?> r) => Expense(
    id: r['id'] as String,
    shiftId: r['shift_id'] as String,
    description: r['description'] as String,
    amount: r['amount'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
  );
}

/// Artikal koji tek treba upisati, npr. iz uvezene tabele.
class NewItem {
  const NewItem({
    required this.name,
    required this.kind,
    required this.price,
    this.initialQty = 0,
    this.imageId,
  });

  final String name;
  final ItemKind kind;
  final int price;
  final int initialQty;
  final String? imageId;
}

/// Slika iz zajedničkog kataloga.
class CatalogImage {
  const CatalogImage({
    required this.id,
    required this.name,
    required this.bytes,
  });

  final String id;
  final String name;
  final Uint8List bytes;
}

/// Izmjena jednog artikla u ispravci zaključene smjene; null znači bez promjene.
class ItemCorrection {
  const ItemCorrection({required this.itemId, this.closing, this.received});

  final String itemId;

  /// Novi ostatak (prebrojano stanje).
  final int? closing;

  /// Nova ukupna primljena količina u smjeni.
  final int? received;
}

/// Kuhinja i predaja novca na kraju smjene, u feninzima.
class Handover {
  const Handover({
    required this.kitchen,
    required this.cash,
    required this.card,
  });

  final int kitchen;
  final int cash;
  final int card;
}

/// Telegram veza lokala: bot na serveru (null dok nije podešen) i povezani razgovori.
class TelegramStatus {
  const TelegramStatus({required this.bot, required this.chats});

  factory TelegramStatus.fromJson(Map<String, dynamic> j) => TelegramStatus(
    bot: j['bot'] as String?,
    chats: [
      for (final c in j['chats'] as List)
        (
          title: c['title'] as String? ?? 'Telegram',
          linkedAt: DateTime.parse(c['created_at'] as String).toLocal(),
        ),
    ],
  );

  final String? bot;
  final List<({String title, DateTime linkedAt})> chats;
}

/// Šta je ispravljeno: ostatak ili primljeno artikla, ili kuhinja i predaja smjene.
enum CorrectionField {
  closing('ostatak'),
  received('primljeno'),
  kitchen('kuhinja'),
  cash('gotovina'),
  card('kartice');

  const CorrectionField(this.label);

  final String label;

  /// Iznos u feninzima, a ne količina.
  bool get isMoney => index >= kitchen.index;
}

/// Zapis o jednoj ispravci zaključene smjene.
class ShiftCorrection {
  const ShiftCorrection({
    required this.shiftId,
    required this.itemName,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.note,
    required this.correctedAt,
  });

  factory ShiftCorrection.fromRemote(Map<String, dynamic> r) => ShiftCorrection(
    shiftId: r['shift_id'] as String,
    itemName: r['item_name'] as String,
    field: CorrectionField.values.byName(r['field'] as String),
    oldValue: r['old_value'] as int?,
    newValue: r['new_value'] as int,
    note: r['note'] as String?,
    correctedAt: DateTime.parse(r['corrected_at'] as String).toLocal(),
  );

  final String shiftId;

  /// Naziv artikla, ili "Kuhinja", "Gotovina", "Kartice" za predaju.
  final String itemName;
  final CorrectionField field;

  /// null kad vrijednost ranije nije bila unesena (npr. predaja stare smjene).
  final int? oldValue;
  final int newValue;
  final String? note;
  final DateTime correctedAt;
}
