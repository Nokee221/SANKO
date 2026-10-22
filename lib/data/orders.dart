import 'models.dart';

/// Sto lokala; gazda ih unosi, a lokal bez stolova kuca narudžbe samo sa brojem.
class VenueTable {
  const VenueTable({required this.id, required this.name});

  final String id;
  final String name;

  factory VenueTable.fromJson(Map<String, dynamic> j) =>
      VenueTable(id: j['id'] as String, name: j['name'] as String);
}

/// Artikal kako ga konobar vidi pri kucanju narudžbe.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.kind = ItemKind.stock,
    this.imageId,
  });

  final String id;
  final String name;

  /// Cijena u feninzima.
  final int price;
  final ItemKind kind;
  final String? imageId;

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
    id: j['id'] as String,
    name: j['name'] as String,
    price: j['price'] as int,
    kind: ItemKind.values.byName(j['kind'] as String? ?? 'stock'),
    imageId: j['image_id'] as String?,
  );
}

/// Artikli i stolovi za kucanje narudžbe.
class Menu {
  const Menu({required this.items, required this.tables});

  final List<MenuItem> items;
  final List<VenueTable> tables;

  factory Menu.fromJson(Map<String, dynamic> j) => Menu(
    items: [
      for (final i in j['items'] as List)
        MenuItem.fromJson(i as Map<String, dynamic>),
    ],
    tables: [
      for (final t in j['tables'] as List)
        VenueTable.fromJson(t as Map<String, dynamic>),
    ],
  );
}

class OrderLine {
  const OrderLine({
    required this.itemId,
    required this.name,
    required this.price,
    required this.qty,
  });

  final String itemId;
  final String name;
  final int price;
  final int qty;

  int get amount => price * qty;

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
    itemId: j['item_id'] as String,
    name: j['name'] as String,
    price: j['price'] as int,
    qty: j['qty'] as int,
  );
}

/// Narudžba sa stola; šank je označi kao gotovu kad je spremi.
class Order {
  const Order({
    required this.id,
    required this.number,
    required this.workerName,
    required this.createdAt,
    required this.lines,
    this.tableName,
    this.note,
    this.doneAt,
  });

  final String id;

  /// Redni broj narudžbe u danu.
  final int number;
  final String workerName;
  final String? tableName;
  final String? note;
  final DateTime createdAt;
  final DateTime? doneAt;
  final List<OrderLine> lines;

  bool get isDone => doneAt != null;
  int get total => lines.fold(0, (sum, l) => sum + l.amount);
  int get itemCount => lines.fold(0, (sum, l) => sum + l.qty);

  /// Sto, ili redni broj kad narudžba nema sto.
  String get title => tableName ?? 'Narudžba $number';

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j['id'] as String,
    number: j['number'] as int,
    workerName: j['worker_name'] as String,
    tableName: j['table_name'] as String?,
    note: j['note'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    doneAt: j['done_at'] == null
        ? null
        : DateTime.parse(j['done_at'] as String).toLocal(),
    lines: [
      for (final l in j['lines'] as List)
        OrderLine.fromJson(l as Map<String, dynamic>),
    ],
  );
}

/// Narudžba koju konobar šalje. Oznaku pravi telefon, pa ponovljeno slanje ne pravi duplikat.
class NewOrder {
  const NewOrder({
    required this.id,
    required this.quantities,
    this.tableId,
    this.note,
  });

  final String id;
  final String? tableId;
  final String? note;

  /// Količina po artiklu, redom kako su kucani.
  final Map<String, int> quantities;

  Map<String, Object?> toPayload() => {
    'id': id,
    'table_id': tableId,
    'note': note,
    'lines': [
      for (final e in quantities.entries)
        if (e.value > 0) {'item_id': e.key, 'qty': e.value},
    ],
  };
}
