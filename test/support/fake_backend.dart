import 'package:sanko/data/db.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/data/orders.dart';
import 'package:sanko/data/repository.dart';
import 'package:sanko/sync/remote_shift.dart';
import 'package:sanko/sync/waiter_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

const testVenueCode = 'TEST01';

/// Zasebna baza u memoriji; svaki poziv daje novu.
Future<Database> openTestDb({bool isolate = true}) {
  sqfliteFfiInit();
  final factory = isolate ? databaseFactoryFfi : databaseFactoryFfiNoIsolate;
  return factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onCreate: (db, _) => createSchema(db),
    ),
  );
}

/// Server u testovima: druga lokalna baza koja igra ulogu Supabasea.
/// Jedan primjerak predstavlja vezu jednog telefona (jednu prijavu).
class FakeBackend implements WaiterBackend {
  FakeBackend(this.server, this.db, {List<Order>? orders})
    : orders = orders ?? [];

  final Repository server;
  final Database db;

  /// Narudžbe na serveru; telefoni istog lokala dijele istu listu.
  final List<Order> orders;

  /// Simulira telefon bez mreže.
  bool offline = false;
  String? sessionWorkerId;

  void _requireNetwork() {
    if (offline) throw const OfflineException();
  }

  @override
  Future<LoginResult> login(String venueCode, String pin) async {
    _requireNetwork();
    if (locked) {
      return const LoginResult.rejected(
        'Previše pogrešnih pokušaja. Pokušajte ponovo za 15 minuta.',
        code: 'locked',
      );
    }
    final worker = venueCode == testVenueCode
        ? await server.workerByPin(pin)
        : null;
    if (worker == null) {
      return const LoginResult.rejected(
        'Pogrešan kod lokala ili PIN.',
        code: 'wrong_pin',
      );
    }
    sessionWorkerId = worker.id;
    return LoginResult.ok(
      workerId: worker.id,
      workerName: worker.name,
      venueName: 'Centar',
      role: worker.role,
    );
  }

  /// Oznaka ovog telefona; smjenu vodi telefon koji ju je zadnji otvorio ili nastavio.
  final String deviceId = const Uuid().v4();

  /// Zaključava prijavu kao kad lokal ima previše pogrešnih pokušaja.
  bool locked = false;

  Future<void> _takeOver(String shiftId) =>
      server.setMeta('owner:$shiftId', deviceId);

  @override
  Future<RemoteShift> startShift(String newShiftId) async {
    _requireNetwork();
    final open = await server.openShift();
    if (open != null) {
      if (open.workerId == sessionWorkerId) {
        await _takeOver(open.id);
        return server.exportShift(open.id);
      }
      throw SankoException('Smjenu još nije zaključio/la ${open.workerName}.');
    }
    final shift = await server.startShift(sessionWorkerId!);
    await _takeOver(shift.id);
    return server.exportShift(shift.id);
  }

  @override
  Future<RemoteShift> fetchShift(String shiftId) async {
    _requireNetwork();
    return server.exportShift(shiftId);
  }

  @override
  Future<DateTime?> shiftClosedAt(String shiftId) async {
    _requireNetwork();
    final rows = await db.query(
      'shifts',
      columns: ['closed_at'],
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (rows.isEmpty) return DateTime.now();
    final ms = rows.single['closed_at'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<List<CatalogImage>> fetchImages(List<String> ids) async {
    _requireNetwork();
    return [
      for (final image in await server.catalogImages())
        if (ids.contains(image.id)) image,
    ];
  }

  @override
  Future<void> pushShift(Map<String, Object?> payload) async {
    _requireNetwork();
    final id = payload['id'] as String;
    final shift = await db.query('shifts', where: 'id = ?', whereArgs: [id]);
    if (shift.isEmpty || shift.single['worker_id'] != sessionWorkerId) {
      throw SankoException('Smjena ne postoji ili nije vaša');
    }
    if (shift.single['closed_by_admin'] == 1) {
      throw ShiftConflictException(
        ShiftConflict.closedByAdmin,
        'Smjenu je zaključio gazda.',
      );
    }
    final owner = await server.meta('owner:$id');
    if (owner != null && owner != deviceId) {
      throw ShiftConflictException(
        ShiftConflict.takenOver,
        'Ova smjena je nastavljena na drugom telefonu.',
      );
    }
    if (shift.single['closed_at'] != null) return;
    if (payload['closed_at'] != null) {
      final counted = {
        for (final c
            in (payload['counts'] as List).cast<Map<String, Object?>>())
          c['item_id'],
      };
      final lines = await db.query(
        'shift_lines',
        columns: ['item_id', 'item_name'],
        where: 'shift_id = ?',
        whereArgs: [id],
      );
      final missing = [
        for (final l in lines)
          if (!counted.contains(l['item_id'])) l['item_name'],
      ];
      if (missing.isNotEmpty) {
        throw ShiftConflictException(
          ShiftConflict.missingCounts,
          'Nije uneseno stanje za: ${missing.join(', ')}. '
          'Unesite ga i ponovo zaključite smjenu.',
        );
      }
    }

    int? ms(Object? iso) => iso == null
        ? null
        : DateTime.parse(iso as String).millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM receipt_lines WHERE receipt_id IN (SELECT id FROM receipts WHERE shift_id = ?)',
        [id],
      );
      await txn.delete('receipts', where: 'shift_id = ?', whereArgs: [id]);
      for (final r
          in (payload['receipts'] as List).cast<Map<String, Object?>>()) {
        await txn.insert('receipts', {
          'id': r['id'],
          'shift_id': id,
          'created_at': ms(r['created_at']),
          'closed_at': ms(r['closed_at']),
        });
        for (final l in (r['lines'] as List).cast<Map<String, Object?>>()) {
          await txn.insert('receipt_lines', {
            'receipt_id': r['id'],
            'item_id': l['item_id'],
            'qty': l['qty'],
          });
        }
      }
      await txn.delete('expenses', where: 'shift_id = ?', whereArgs: [id]);
      for (final e
          in (payload['expenses'] as List).cast<Map<String, Object?>>()) {
        await txn.insert('expenses', {
          'id': e['id'],
          'shift_id': id,
          'description': e['description'],
          'amount': e['amount'],
          'created_at': ms(e['created_at']),
        });
      }
      await txn.update(
        'shift_lines',
        {'closing_qty': null},
        where: 'shift_id = ?',
        whereArgs: [id],
      );
      for (final c
          in (payload['counts'] as List).cast<Map<String, Object?>>()) {
        await txn.update(
          'shift_lines',
          {'closing_qty': c['closing_qty']},
          where: 'shift_id = ? AND item_id = ?',
          whereArgs: [id, c['item_id']],
        );
      }
      await txn.update(
        'shifts',
        {
          'kitchen': payload['kitchen'],
          'cash': payload['cash'],
          'card': payload['card'],
          if (payload['closed_at'] != null)
            'closed_at': ms(payload['closed_at']),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    server.refresh();
  }

  @override
  Future<Menu> fetchMenu() async {
    _requireNetwork();
    return Menu(
      items: [
        for (final i in await server.items())
          MenuItem(
            id: i.id,
            name: i.name,
            price: i.price,
            kind: i.kind,
            imageId: i.imageId,
          ),
      ],
      tables: await server.tables(),
    );
  }

  @override
  Future<Order> placeOrder(NewOrder order) async {
    _requireNetwork();
    final existing = orders.where((o) => o.id == order.id).firstOrNull;
    if (existing != null) return existing;
    final payload = order.toPayload();
    final lines = (payload['lines'] as List).cast<Map<String, Object?>>();
    if (lines.isEmpty) throw SankoException('Narudžba je prazna.');
    final items = {for (final i in await server.items()) i.id: i};
    final worker = (await server.workers()).firstWhere(
      (w) => w.id == sessionWorkerId,
    );
    final table = order.tableId == null
        ? null
        : (await server.tables()).firstWhere((t) => t.id == order.tableId);
    final placed = Order(
      id: order.id,
      number: orders.length + 1,
      workerName: worker.name,
      tableName: table?.name,
      note: order.note,
      createdAt: DateTime.now(),
      lines: [
        for (final l in lines)
          OrderLine(
            itemId: l['item_id'] as String,
            name: items[l['item_id']]!.name,
            price: items[l['item_id']]!.price,
            qty: l['qty'] as int,
          ),
      ],
    );
    orders.add(placed);
    return placed;
  }

  @override
  Future<List<Order>> fetchOrders({required bool mine}) async {
    _requireNetwork();
    if (!mine) {
      return [
        for (final o in orders)
          if (!o.isDone) o,
      ];
    }
    final name = (await server.workers())
        .firstWhere((w) => w.id == sessionWorkerId)
        .name;
    return [
      for (final o in orders.reversed)
        if (o.workerName == name) o,
    ];
  }

  @override
  Future<void> setOrderDone(String orderId, {required bool done}) async {
    _requireNetwork();
    final i = orders.indexWhere((o) => o.id == orderId);
    final o = orders[i];
    orders[i] = Order(
      id: o.id,
      number: o.number,
      workerName: o.workerName,
      tableName: o.tableName,
      note: o.note,
      createdAt: o.createdAt,
      doneAt: done ? DateTime.now() : null,
      lines: o.lines,
    );
  }
}
