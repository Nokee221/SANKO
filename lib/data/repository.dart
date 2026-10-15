import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/obracun.dart';
import '../domain/report.dart';
import '../domain/stats.dart';
import '../sync/remote_shift.dart';
import 'admin_data.dart';
import 'demo_items.dart';
import 'errors.dart';
import 'models.dart';

export 'errors.dart';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _shiftSelect = '''
  SELECT s.*, w.name AS worker_name
  FROM shifts s JOIN workers w ON w.id = s.worker_id
''';

/// Jedini ulaz u lokalnu bazu. Javlja promjene preko [notifyListeners] nakon svakog upisa.
class Repository extends ChangeNotifier implements AdminData {
  Repository(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  int get _nowMs => _now().millisecondsSinceEpoch;

  // --- Radnici ---

  @override
  Future<List<Worker>> workers() async {
    final rows = await _db.query(
      'workers',
      where: 'active = 1',
      orderBy: 'name',
    );
    return rows.map(Worker.fromRow).toList();
  }

  Future<Worker?> workerByPin(String pin) async {
    final rows = await _db.query(
      'workers',
      where: 'active = 1 AND pin = ?',
      whereArgs: [pin],
    );
    return rows.isEmpty ? null : Worker.fromRow(rows.first);
  }

  @override
  Future<void> addWorker({required String name, required String pin}) async {
    if (name.trim().isEmpty) throw SankoException('Unesite ime radnika.');
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw SankoException('PIN mora imati tačno 4 cifre.');
    }
    if (await workerByPin(pin) != null) {
      throw SankoException('Taj PIN već koristi drugi radnik.');
    }
    await _db.insert('workers', {
      'id': _uuid.v4(),
      'name': name.trim(),
      'pin': pin,
      'created_at': _nowMs,
    });
    notifyListeners();
  }

  /// Radnik se samo isključuje, da stare smjene zadrže ime.
  @override
  Future<void> removeWorker(String id) async {
    final open = await openShift();
    if (open != null && open.workerId == id) {
      throw SankoException(
        'Radnik ima otvorenu smjenu. Prvo je treba zaključiti.',
      );
    }
    await _db.update(
      'workers',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  // --- Artikli ---

  @override
  Future<List<Item>> items() async {
    final rows = await _db.query(
      'items',
      where: 'active = 1',
      orderBy: 'sort_order, name',
    );
    return rows.map(Item.fromRow).toList();
  }

  @override
  Future<bool> itemHasHistory(String id) async {
    final rows = await _db.query(
      'shift_lines',
      where: 'item_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> addItem({
    required String name,
    required ItemKind kind,
    required int price,
    int initialQty = 0,
    String? imageId,
    int? minQty,
    int? parQty,
  }) async {
    if (name.trim().isEmpty) throw SankoException('Unesite naziv artikla.');
    await _db.transaction((txn) async {
      final next = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), 0) + 1 AS n FROM items',
      );
      final id = _uuid.v4();
      final sortOrder = next.first['n'] as int;
      await txn.insert('items', {
        'id': id,
        'name': name.trim(),
        'kind': kind.name,
        'price': price,
        'initial_qty': initialQty,
        'sort_order': sortOrder,
        'created_at': _nowMs,
        'image_id': imageId,
        'min_qty': minQty,
        'par_qty': parQty,
      });
      // Artikal dodan usred smjene ulazi odmah u nju, da ga konobar može primiti i prebrojati.
      final open = await txn.query('shifts', where: 'closed_at IS NULL');
      if (open.isNotEmpty) {
        await txn.insert('shift_lines', {
          'shift_id': open.first['id'],
          'item_id': id,
          'item_name': name.trim(),
          'kind': kind.name,
          'price': price,
          'sort_order': sortOrder,
          'opening_qty': initialQty,
        });
      }
    });
    notifyListeners();
  }

  /// Nova cijena i naziv važe od sljedeće smjene.
  @override
  Future<void> updateItem(Item item) async {
    if (item.name.trim().isEmpty) {
      throw SankoException('Unesite naziv artikla.');
    }
    await _db.update(
      'items',
      {
        'name': item.name.trim(),
        'kind': item.kind.name,
        'price': item.price,
        'initial_qty': item.initialQty,
        'image_id': item.imageId,
        'min_qty': item.minQty,
        'par_qty': item.parQty,
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
    notifyListeners();
  }

  /// Artikal se samo isključuje; ostaje u otvorenoj smjeni i u starim obračunima.
  @override
  Future<void> removeItem(String id) async {
    await _db.update('items', {'active': 0}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  // --- Smjene ---

  Future<Shift?> openShift() async {
    final rows = await _db.rawQuery('$_shiftSelect WHERE s.closed_at IS NULL');
    return rows.isEmpty ? null : Shift.fromRow(rows.first);
  }

  Future<Shift> shiftById(String id) async {
    final rows = await _db.rawQuery('$_shiftSelect WHERE s.id = ?', [id]);
    return Shift.fromRow(rows.single);
  }

  @override
  Future<List<Shift>> shiftsOn(DateTime day) async {
    final rows = await _db.rawQuery(
      '$_shiftSelect WHERE s.business_date = ? ORDER BY s.seq',
      [_dateKey(day)],
    );
    return rows.map(Shift.fromRow).toList();
  }

  /// Otvara smjenu za radnika. Početno stanje svakog artikla je krajnje stanje
  /// iz zadnje zaključene smjene u kojoj je bio, inače početno stanje artikla.
  Future<Shift> startShift(String workerId) async {
    final id = _uuid.v4();
    await _db.transaction((txn) async {
      final open = await txn.rawQuery(
        '$_shiftSelect WHERE s.closed_at IS NULL',
      );
      if (open.isNotEmpty) {
        throw SankoException(
          'Smjenu još nije zaključio/la ${open.first['worker_name']}.',
        );
      }
      final now = _now();
      final date = _dateKey(now);
      final seq = await txn.rawQuery(
        'SELECT COALESCE(MAX(seq), 0) + 1 AS n FROM shifts WHERE business_date = ?',
        [date],
      );
      await txn.insert('shifts', {
        'id': id,
        'worker_id': workerId,
        'business_date': date,
        'seq': seq.first['n'],
        'opened_at': now.millisecondsSinceEpoch,
      });
      await txn.rawInsert(
        '''
        INSERT INTO shift_lines (shift_id, item_id, item_name, kind, price, sort_order, opening_qty)
        SELECT ?, i.id, i.name, i.kind, i.price, i.sort_order,
          COALESCE(
            (SELECT l.closing_qty
             FROM shift_lines l JOIN shifts s ON s.id = l.shift_id
             WHERE l.item_id = i.id AND s.closed_at IS NOT NULL
             ORDER BY s.opened_at DESC LIMIT 1),
            i.initial_qty)
        FROM items i
        WHERE i.active = 1
        ''',
        [id],
      );
    });
    notifyListeners();
    return shiftById(id);
  }

  /// Upisuje prebrojano stanje artikla; null briše unos.
  Future<void> setClosingQty(String shiftId, String itemId, int? qty) async {
    await _requireOpen(shiftId);
    if (qty != null) {
      final line = await _db.query(
        'shift_lines',
        where: 'shift_id = ? AND item_id = ?',
        whereArgs: [shiftId, itemId],
      );
      if (qty < 0) throw SankoException('Stanje ne može biti negativno.');
      if (line.single['kind'] == ItemKind.counter.name &&
          qty < (line.single['opening_qty'] as int)) {
        throw SankoException(
          'Brojač ne može biti manji od prethodnog stanja (${line.single['opening_qty']}).',
        );
      }
    }
    await _db.update(
      'shift_lines',
      {'closing_qty': qty},
      where: 'shift_id = ? AND item_id = ?',
      whereArgs: [shiftId, itemId],
    );
    await _changed(shiftId);
  }

  /// Zaključuje smjenu sa kuhinjom i predajom novca. Nakon ovoga se smjena više
  /// ne može mijenjati.
  Future<void> closeShift(String shiftId, {Handover? handover}) async {
    await _db.transaction((txn) async {
      final shift = await txn.query(
        'shifts',
        where: 'id = ?',
        whereArgs: [shiftId],
      );
      if (shift.single['closed_at'] != null) return;
      final missing = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM shift_lines WHERE shift_id = ? AND closing_qty IS NULL',
        [shiftId],
      );
      if ((missing.first['n'] as int) > 0) {
        throw SankoException('Nije uneseno stanje za sve artikle.');
      }
      final draft = await txn.rawQuery(
        '''
        SELECT COUNT(*) AS n FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
        WHERE r.shift_id = ? AND r.closed_at IS NULL
        ''',
        [shiftId],
      );
      if ((draft.first['n'] as int) > 0) {
        throw SankoException(
          'Imate ULAZ koji nije zaključen. Zaključite ga ili obrišite unose.',
        );
      }
      if (handover != null) _checkHandover(handover);
      await txn.update(
        'shifts',
        {
          'closed_at': _nowMs,
          'kitchen': handover?.kitchen,
          'cash': handover?.cash,
          'card': handover?.card,
        },
        where: 'id = ?',
        whereArgs: [shiftId],
      );
    });
    await _changed(shiftId);
  }

  void _checkHandover(Handover h) {
    if (h.kitchen < 0 || h.cash < 0 || h.card < 0) {
      throw SankoException('Iznos ne može biti negativan.');
    }
  }

  @override
  Future<void> setHandover(
    String shiftId,
    Handover handover, {
    String? note,
  }) async {
    _checkHandover(handover);
    final shift = (await _db.query(
      'shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
    )).single;
    if (shift['closed_at'] == null) {
      throw SankoException(
        'Smjena još nije zaključena; predaju unosi konobar pri zaključenju.',
      );
    }
    final cleanNote = note?.trim().isEmpty ?? true ? null : note!.trim();
    await _db.transaction((txn) async {
      for (final (label, field, value) in [
        ('Kuhinja', CorrectionField.kitchen, handover.kitchen),
        ('Gotovina', CorrectionField.cash, handover.cash),
        ('Kartice', CorrectionField.card, handover.card),
      ]) {
        final old = shift[field.name] as int?;
        if (old == value) continue;
        await txn.insert('corrections', {
          'id': _uuid.v4(),
          'shift_id': shiftId,
          'item_name': label,
          'field': field.name,
          'old_value': old,
          'new_value': value,
          'note': cleanNote,
          'corrected_at': _nowMs,
        });
      }
      await txn.update(
        'shifts',
        {
          'kitchen': handover.kitchen,
          'cash': handover.cash,
          'card': handover.card,
        },
        where: 'id = ?',
        whereArgs: [shiftId],
      );
    });
    notifyListeners();
  }

  @override
  Future<List<ShiftSummary>> shiftSummaries(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      '$_shiftSelect WHERE s.closed_at IS NOT NULL AND s.business_date BETWEEN ? AND ? '
      'ORDER BY s.business_date, s.seq',
      [_dateKey(from), _dateKey(to)],
    );
    final summaries = <ShiftSummary>[];
    for (final r in rows) {
      final o = await obracunForShift(r['id'] as String);
      summaries.add(
        ShiftSummary(
          shiftId: r['id'] as String,
          businessDate: DateTime.parse(r['business_date'] as String),
          seq: r['seq'] as int,
          workerName: r['worker_name'] as String,
          sank: o.sank,
          expenses: o.expenses,
          kitchen: r['kitchen'] as int?,
          cash: r['cash'] as int?,
          card: r['card'] as int?,
          anomalies: [
            for (final l in o.lines)
              if (l.hasAnomaly) l.name,
          ],
        ),
      );
    }
    return summaries;
  }

  // Telegram radi samo kroz server; lokalna baza ga nema.
  @override
  Future<TelegramStatus> telegramStatus() async =>
      const TelegramStatus(bot: null, chats: []);

  @override
  Future<String> telegramLink() async =>
      throw SankoException('Telegram obavještenja rade samo uz server.');

  @override
  Future<void> telegramUnlink() async {}

  /// Povećava reviziju smjene, po kojoj sinhronizacija zna da ima šta poslati.
  Future<void> _changed(String shiftId) async {
    await _db.rawUpdate('UPDATE shifts SET dirty = dirty + 1 WHERE id = ?', [
      shiftId,
    ]);
    notifyListeners();
  }

  @override
  Future<List<StatLine>> statLines(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.item_id, l.item_name, l.kind, l.price, l.sort_order, l.opening_qty, l.closing_qty,
        s.business_date, s.id AS shift_id, s.seq, w.name AS worker_name,
        (SELECT COALESCE(SUM(rl.qty), 0)
         FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
         WHERE r.shift_id = s.id AND r.closed_at IS NOT NULL AND rl.item_id = l.item_id
        ) AS received
      FROM shifts s
      JOIN shift_lines l ON l.shift_id = s.id
      JOIN workers w ON w.id = s.worker_id
      WHERE s.closed_at IS NOT NULL AND s.business_date BETWEEN ? AND ?
      ORDER BY s.business_date, s.seq, l.sort_order
      ''',
      [_dateKey(from), _dateKey(to)],
    );
    return [
      for (final r in rows)
        StatLine(
          itemId: r['item_id'] as String,
          itemName: r['item_name'] as String,
          kind: ItemKind.values.byName(r['kind'] as String),
          sortOrder: r['sort_order'] as int,
          businessDate: DateTime.parse(r['business_date'] as String),
          shiftId: r['shift_id'] as String,
          seq: r['seq'] as int,
          workerName: r['worker_name'] as String,
          received: r['received'] as int,
          price: r['price'] as int,
          consumed: ObracunLine.forShift(
            itemId: r['item_id'] as String,
            name: r['item_name'] as String,
            kind: ItemKind.values.byName(r['kind'] as String),
            price: 0,
            opening: r['opening_qty'] as int,
            received: r['received'] as int,
            closing: r['closing_qty'] as int,
          ).consumed!,
        ),
    ];
  }

  @override
  Future<void> correctShift(
    String shiftId,
    List<ItemCorrection> changes, {
    String? note,
  }) async {
    final shift = await shiftById(shiftId);
    if (!shift.isClosed) {
      throw SankoException(
        'Smjena još nije zaključena; ispravljaju se samo zaključene smjene.',
      );
    }
    final cleanNote = note?.trim().isEmpty ?? true ? null : note!.trim();
    // Čita se prije transakcije; poziv baze izvan transakcije unutar nje bi je zaključao.
    final lines = await obracunForShift(shiftId);
    await _db.transaction((txn) async {
      for (final c in changes) {
        final line = lines.lines.where((l) => l.itemId == c.itemId).firstOrNull;
        if (line == null) throw SankoException('Artikal nije u ovoj smjeni');
        Future<void> record(String field, int oldValue, int newValue) =>
            txn.insert('corrections', {
              'id': _uuid.v4(),
              'shift_id': shiftId,
              'item_name': line.name,
              'field': field,
              'old_value': oldValue,
              'new_value': newValue,
              'note': cleanNote,
              'corrected_at': _nowMs,
            });

        final received = c.received;
        if (received != null && received != line.received) {
          if (line.kind == ItemKind.counter) {
            throw SankoException('${line.name} je brojač i nema ulaz.');
          }
          final receiptId = _uuid.v4();
          await txn.insert('receipts', {
            'id': receiptId,
            'shift_id': shiftId,
            'created_at': _nowMs,
            'closed_at': _nowMs,
          });
          await txn.insert('receipt_lines', {
            'receipt_id': receiptId,
            'item_id': c.itemId,
            'qty': received - line.received,
          });
          await record('received', line.received, received);
        }

        final closing = c.closing;
        if (closing != null && closing != line.closing) {
          if (closing < 0) {
            throw SankoException('Ostatak ne može biti negativan.');
          }
          if (line.kind == ItemKind.counter && closing < line.opening) {
            throw SankoException(
              'Brojač za ${line.name} ne može biti manji od prethodnog stanja (${line.opening}).',
            );
          }
          await txn.update(
            'shift_lines',
            {'closing_qty': closing},
            where: 'shift_id = ? AND item_id = ?',
            whereArgs: [shiftId, c.itemId],
          );
          await record('closing', line.closing!, closing);
          // Sljedeća smjena u kojoj je artikal bio počinje od ispravljenog ostatka.
          final next = await txn.rawQuery(
            '''
            SELECT l.shift_id, l.closing_qty FROM shifts s
            JOIN shift_lines l ON l.shift_id = s.id AND l.item_id = ?
            WHERE s.opened_at > ? ORDER BY s.opened_at LIMIT 1
            ''',
            [c.itemId, shift.openedAt.millisecondsSinceEpoch],
          );
          if (next.isNotEmpty) {
            final nextClosing = next.single['closing_qty'] as int?;
            if (line.kind == ItemKind.counter &&
                nextClosing != null &&
                nextClosing < closing) {
              throw SankoException(
                'Brojač za ${line.name} bi u sljedećoj smjeni bio manji od početnog stanja.',
              );
            }
            await txn.update(
              'shift_lines',
              {'opening_qty': closing},
              where: 'shift_id = ? AND item_id = ?',
              whereArgs: [next.single['shift_id'], c.itemId],
            );
          }
        }
      }
    });
    notifyListeners();
  }

  @override
  Future<List<ShiftCorrection>> corrections(List<String> shiftIds) async {
    if (shiftIds.isEmpty) return const [];
    final rows = await _db.query(
      'corrections',
      where: 'shift_id IN (${List.filled(shiftIds.length, '?').join(', ')})',
      whereArgs: shiftIds,
      orderBy: 'corrected_at',
    );
    return [
      for (final r in rows)
        ShiftCorrection(
          shiftId: r['shift_id'] as String,
          itemName: r['item_name'] as String,
          field: CorrectionField.values.byName(r['field'] as String),
          oldValue: r['old_value'] as int?,
          newValue: r['new_value'] as int,
          note: r['note'] as String?,
          correctedAt: DateTime.fromMillisecondsSinceEpoch(
            r['corrected_at'] as int,
          ),
        ),
    ];
  }

  @override
  Future<List<StockLevel>> currentStock() async {
    final rows = await _db.rawQuery('''
      SELECT i.id, i.name, i.sort_order,
        COALESCE(
          (SELECT l.closing_qty FROM shift_lines l JOIN shifts s ON s.id = l.shift_id
           WHERE l.item_id = i.id AND s.closed_at IS NOT NULL
           ORDER BY s.opened_at DESC LIMIT 1),
          i.initial_qty)
        + COALESCE(
          (SELECT SUM(rl.qty) FROM receipt_lines rl
           JOIN receipts r ON r.id = rl.receipt_id
           JOIN shifts s ON s.id = r.shift_id
           WHERE rl.item_id = i.id AND s.closed_at IS NULL AND r.closed_at IS NOT NULL),
          0) AS stock
      FROM items i
      WHERE i.active = 1 AND i.kind = 'stock'
      ORDER BY i.sort_order
    ''');
    return [
      for (final r in rows)
        StockLevel(
          itemId: r['id'] as String,
          name: r['name'] as String,
          sortOrder: r['sort_order'] as int,
          stock: r['stock'] as int,
        ),
    ];
  }

  @override
  Future<void> adminCloseShift(
    String shiftId,
    Map<String, int> counts, {
    Handover? handover,
  }) async {
    await _requireOpen(shiftId);
    await _db.transaction((txn) async {
      for (final e in counts.entries) {
        await txn.update(
          'shift_lines',
          {'closing_qty': e.value},
          where: 'shift_id = ? AND item_id = ?',
          whereArgs: [shiftId, e.key],
        );
      }
      // Ulaz koji konobar nije zaključio se odbacuje.
      await txn.rawDelete(
        '''
        DELETE FROM receipt_lines WHERE receipt_id IN
          (SELECT id FROM receipts WHERE shift_id = ? AND closed_at IS NULL)
        ''',
        [shiftId],
      );
      await txn.delete(
        'receipts',
        where: 'shift_id = ? AND closed_at IS NULL',
        whereArgs: [shiftId],
      );
    });
    await closeShift(shiftId, handover: handover);
  }

  Future<void> _requireOpen(String shiftId) async {
    final rows = await _db.query(
      'shifts',
      where: 'id = ?',
      whereArgs: [shiftId],
    );
    if (rows.single['closed_at'] != null) {
      throw SankoException('Smjena je zaključena i ne može se mijenjati.');
    }
  }

  // --- Ulaz ---

  /// Količine u ulazu koji je još u unosu, po artiklu.
  Future<Map<String, int>> draftReceipt(String shiftId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT rl.item_id, rl.qty FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
      WHERE r.shift_id = ? AND r.closed_at IS NULL
      ''',
      [shiftId],
    );
    return {for (final r in rows) r['item_id'] as String: r['qty'] as int};
  }

  /// Količina može biti negativna (povrat ili ispravka); null ili 0 briše unos.
  Future<void> setDraftReceiptQty(
    String shiftId,
    String itemId,
    int? qty,
  ) async {
    await _requireOpen(shiftId);
    await _db.transaction((txn) async {
      final draft = await txn.query(
        'receipts',
        where: 'shift_id = ? AND closed_at IS NULL',
        whereArgs: [shiftId],
      );
      var receiptId = draft.isEmpty ? null : draft.first['id'] as String;
      if (receiptId == null) {
        receiptId = _uuid.v4();
        await txn.insert('receipts', {
          'id': receiptId,
          'shift_id': shiftId,
          'created_at': _nowMs,
        });
      }
      if (qty == null || qty == 0) {
        await txn.delete(
          'receipt_lines',
          where: 'receipt_id = ? AND item_id = ?',
          whereArgs: [receiptId, itemId],
        );
      } else {
        await txn.insert('receipt_lines', {
          'receipt_id': receiptId,
          'item_id': itemId,
          'qty': qty,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await _changed(shiftId);
  }

  Future<void> closeDraftReceipt(String shiftId) async {
    await _requireOpen(shiftId);
    if ((await draftReceipt(shiftId)).isEmpty) {
      throw SankoException('Ulaz je prazan.');
    }
    await _db.update(
      'receipts',
      {'closed_at': _nowMs},
      where: 'shift_id = ? AND closed_at IS NULL',
      whereArgs: [shiftId],
    );
    await _changed(shiftId);
  }

  /// Broj zaključenih ulaza u smjeni.
  Future<int> closedReceiptCount(String shiftId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n FROM receipts WHERE shift_id = ? AND closed_at IS NOT NULL',
      [shiftId],
    );
    return rows.first['n'] as int;
  }

  // --- Rashod ---

  @override
  Future<List<Expense>> expenses(String shiftId) async {
    final rows = await _db.query(
      'expenses',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'created_at',
    );
    return rows.map(Expense.fromRow).toList();
  }

  Future<void> addExpense(
    String shiftId, {
    required String description,
    required int amount,
  }) async {
    await _requireOpen(shiftId);
    if (description.trim().isEmpty) {
      throw SankoException('Unesite opis rashoda.');
    }
    if (amount <= 0) throw SankoException('Unesite iznos rashoda.');
    await _db.insert('expenses', {
      'id': _uuid.v4(),
      'shift_id': shiftId,
      'description': description.trim(),
      'amount': amount,
      'created_at': _nowMs,
    });
    await _changed(shiftId);
  }

  Future<void> deleteExpense(Expense expense) async {
    await _requireOpen(expense.shiftId);
    await _db.delete('expenses', where: 'id = ?', whereArgs: [expense.id]);
    await _changed(expense.shiftId);
  }

  // --- Obračun ---

  /// U primljeno ulaze samo zaključeni ulazi.
  @override
  Future<Obracun> obracunForShift(String shiftId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.*,
        (SELECT COALESCE(SUM(rl.qty), 0)
         FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
         WHERE r.shift_id = l.shift_id AND r.closed_at IS NOT NULL AND rl.item_id = l.item_id
        ) AS received
      FROM shift_lines l
      WHERE l.shift_id = ?
      ORDER BY l.sort_order, l.item_name
      ''',
      [shiftId],
    );
    final spent = await _db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS n FROM expenses WHERE shift_id = ?',
      [shiftId],
    );
    final handover = await _handover(shiftId);
    return Obracun(
      kitchen: handover['kitchen'] as int? ?? 0,
      cash: handover['cash'] as int?,
      card: handover['card'] as int?,
      lines: [
        for (final r in rows)
          ObracunLine.forShift(
            itemId: r['item_id'] as String,
            name: r['item_name'] as String,
            kind: ItemKind.values.byName(r['kind'] as String),
            price: r['price'] as int,
            opening: r['opening_qty'] as int,
            received: r['received'] as int,
            closing: r['closing_qty'] as int?,
          ),
      ],
      expenses: spent.first['n'] as int,
    );
  }

  /// Kuhinja i predaja smjene, kako su upisane u bazi.
  Future<Map<String, Object?>> _handover(String shiftId) async =>
      (await _db.query(
        'shifts',
        columns: ['kitchen', 'cash', 'card'],
        where: 'id = ?',
        whereArgs: [shiftId],
      )).single;

  Future<Obracun> obracunForDay(DateTime day) async {
    final shifts = await shiftsOn(day);
    return Obracun.forDay([
      for (final s in shifts) await obracunForShift(s.id),
    ]);
  }

  // --- Primjer podataka ---

  @override
  Future<void> addItems(List<NewItem> items) async {
    for (final i in items) {
      await addItem(
        name: i.name,
        kind: i.kind,
        price: i.price,
        initialQty: i.initialQty,
        imageId: i.imageId,
      );
    }
  }

  /// Artikli i stanja iz primjera knjige šanka, za isprobavanje.
  @override
  Future<void> seedDemoItems() async {
    for (final (name, kind, price, qty) in demoItems) {
      await addItem(name: name, kind: kind, price: price, initialQty: qty);
    }
  }

  @override
  void refresh() => notifyListeners();

  // --- Sinhronizacija (telefon) ---

  Future<String?> meta(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await _db.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('meta', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Pamti radnika nakon uspješne prijave na serveru, da se kasnije može prijaviti i bez mreže.
  Future<void> cacheWorker({
    required String id,
    required String name,
    required String pin,
  }) async {
    await _db.update(
      'workers',
      {'active': 0},
      where: 'pin = ? AND id <> ?',
      whereArgs: [pin, id],
    );
    await _db.rawInsert(
      '''
      INSERT INTO workers (id, name, pin, active, created_at) VALUES (?, ?, ?, 1, ?)
      ON CONFLICT (id) DO UPDATE SET name = excluded.name, pin = excluded.pin, active = 1
      ''',
      [id, name, pin, _nowMs],
    );
  }

  /// Server je odbio ovaj PIN, pa ne smije više važiti ni bez mreže.
  Future<void> forgetPin(String pin) async {
    await _db.update(
      'workers',
      {'active': 0},
      where: 'pin = ?',
      whereArgs: [pin],
    );
  }

  /// Cijelo stanje smjene, u obliku koji se šalje na server.
  Future<RemoteShift> exportShift(String shiftId) async {
    final shift = await shiftById(shiftId);
    final handover = await _handover(shiftId);
    final lines = await _db.rawQuery(
      '''
      SELECT l.*, i.image_id FROM shift_lines l JOIN items i ON i.id = l.item_id
      WHERE l.shift_id = ?
      ORDER BY l.sort_order, l.item_name
      ''',
      [shiftId],
    );
    final receipts = await _db.query(
      'receipts',
      where: 'shift_id = ?',
      whereArgs: [shiftId],
      orderBy: 'created_at',
    );
    final receiptLines = await _db.rawQuery(
      '''
      SELECT rl.* FROM receipt_lines rl JOIN receipts r ON r.id = rl.receipt_id
      WHERE r.shift_id = ?
      ''',
      [shiftId],
    );
    DateTime? time(Object? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
    return RemoteShift(
      id: shift.id,
      workerId: shift.workerId,
      workerName: shift.workerName,
      businessDate: _dateKey(shift.businessDate),
      seq: shift.seq,
      openedAt: shift.openedAt,
      closedAt: shift.closedAt,
      kitchen: handover['kitchen'] as int?,
      cash: handover['cash'] as int?,
      card: handover['card'] as int?,
      lines: [
        for (final l in lines)
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
        for (final r in receipts)
          RemoteReceipt(
            id: r['id'] as String,
            createdAt: time(r['created_at'])!,
            closedAt: time(r['closed_at']),
            lines: {
              for (final l in receiptLines)
                if (l['receipt_id'] == r['id'])
                  l['item_id'] as String: l['qty'] as int,
            },
          ),
      ],
      expenses: [
        for (final e in await expenses(shiftId))
          RemoteExpense(
            id: e.id,
            description: e.description,
            amount: e.amount,
            createdAt: e.createdAt,
          ),
      ],
    );
  }

  /// Preuzima smjenu sa servera. Ako je telefon već ima, dodaje samo stavke koje nedostaju
  /// (artikal koji je gazda dodao usred smjene); lokalni unosi ostaju netaknuti.
  Future<void> importShift(RemoteShift remote) async {
    var changed = false;
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'shifts',
        where: 'id = ?',
        whereArgs: [remote.id],
      );
      final isNew = existing.isEmpty;
      // Gazda je zaključio smjenu s desktopa: na telefonu od tada važi stanje sa servera.
      final adopt =
          !isNew &&
          existing.single['closed_at'] == null &&
          remote.closedAt != null;
      if (isNew) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO workers (id, name, pin, active, created_at) VALUES (?, ?, ?, 0, ?)',
          [remote.workerId, remote.workerName, '', _nowMs],
        );
        await txn.insert('shifts', {
          'id': remote.id,
          'worker_id': remote.workerId,
          'business_date': remote.businessDate,
          'seq': remote.seq,
          'opened_at': remote.openedAt.millisecondsSinceEpoch,
          'closed_at': remote.closedAt?.millisecondsSinceEpoch,
          'kitchen': remote.kitchen,
          'cash': remote.cash,
          'card': remote.card,
        });
        changed = true;
      }
      final known = {
        for (final r in await txn.query(
          'shift_lines',
          columns: ['item_id'],
          where: 'shift_id = ?',
          whereArgs: [remote.id],
        ))
          r['item_id'] as String,
      };
      for (final l in remote.lines.where((l) => !known.contains(l.itemId))) {
        await txn.rawInsert(
          '''
          INSERT OR IGNORE INTO items (id, name, kind, price, initial_qty, sort_order, created_at)
          VALUES (?, ?, ?, ?, 0, ?, ?)
          ''',
          [l.itemId, l.name, l.kind, l.price, l.sortOrder, _nowMs],
        );
        await txn.insert('shift_lines', {
          'shift_id': remote.id,
          'item_id': l.itemId,
          'item_name': l.name,
          'kind': l.kind,
          'price': l.price,
          'sort_order': l.sortOrder,
          'opening_qty': l.openingQty,
          'closing_qty': isNew ? l.closingQty : null,
        });
        changed = true;
      }
      // Gazda je možda ispravio prethodnu smjenu, pa se mijenja početno stanje.
      if (!isNew) {
        for (final l in remote.lines) {
          final updated = await txn.rawUpdate(
            'UPDATE shift_lines SET opening_qty = ? WHERE shift_id = ? AND item_id = ? AND opening_qty <> ?',
            [l.openingQty, remote.id, l.itemId, l.openingQty],
          );
          if (updated > 0) changed = true;
        }
      }
      // Gazda može naknadno promijeniti sliku artikla.
      for (final l in remote.lines) {
        final updated = await txn.rawUpdate(
          'UPDATE items SET image_id = ? WHERE id = ? AND image_id IS NOT ?',
          [l.imageId, l.itemId, l.imageId],
        );
        if (updated > 0) changed = true;
      }
      if (!isNew && !adopt) return;
      if (adopt) {
        await txn.rawDelete(
          'DELETE FROM receipt_lines WHERE receipt_id IN (SELECT id FROM receipts WHERE shift_id = ?)',
          [remote.id],
        );
        await txn.delete(
          'receipts',
          where: 'shift_id = ?',
          whereArgs: [remote.id],
        );
        await txn.delete(
          'expenses',
          where: 'shift_id = ?',
          whereArgs: [remote.id],
        );
        for (final l in remote.lines) {
          await txn.update(
            'shift_lines',
            {'closing_qty': l.closingQty},
            where: 'shift_id = ? AND item_id = ?',
            whereArgs: [remote.id, l.itemId],
          );
        }
        await txn.update(
          'shifts',
          {
            'closed_at': remote.closedAt!.millisecondsSinceEpoch,
            'dirty': 0,
            'kitchen': remote.kitchen,
            'cash': remote.cash,
            'card': remote.card,
          },
          where: 'id = ?',
          whereArgs: [remote.id],
        );
        changed = true;
      }
      for (final r in remote.receipts) {
        await txn.insert('receipts', {
          'id': r.id,
          'shift_id': remote.id,
          'created_at': r.createdAt.millisecondsSinceEpoch,
          'closed_at': r.closedAt?.millisecondsSinceEpoch,
        });
        for (final e in r.lines.entries) {
          await txn.insert('receipt_lines', {
            'receipt_id': r.id,
            'item_id': e.key,
            'qty': e.value,
          });
        }
      }
      for (final e in remote.expenses) {
        await txn.insert('expenses', {
          'id': e.id,
          'shift_id': remote.id,
          'description': e.description,
          'amount': e.amount,
          'created_at': e.createdAt.millisecondsSinceEpoch,
        });
      }
    });
    if (changed) notifyListeners();
  }

  // --- Slike artikala ---

  @override
  Future<List<CatalogImage>> catalogImages() async {
    final rows = await _db.query('images', orderBy: 'name');
    return [
      for (final r in rows)
        CatalogImage(
          id: r['id'] as String,
          name: r['name'] as String,
          bytes: r['data'] as Uint8List,
        ),
    ];
  }

  /// Sve slike koje artikli koriste.
  Future<List<String>> usedImageIds() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT image_id FROM items WHERE image_id IS NOT NULL',
    );
    return [for (final r in rows) r['image_id'] as String];
  }

  /// Slike koje artikli koriste, a telefon ih još nema.
  Future<List<String>> missingImageIds() async {
    final rows = await _db.rawQuery('''
      SELECT DISTINCT image_id FROM items
      WHERE image_id IS NOT NULL AND image_id NOT IN (SELECT id FROM images)
    ''');
    return [for (final r in rows) r['image_id'] as String];
  }

  Future<void> saveImages(List<CatalogImage> images) async {
    if (images.isEmpty) return;
    final batch = _db.batch();
    for (final image in images) {
      batch.insert('images', {
        'id': image.id,
        'name': image.name,
        'data': image.bytes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }

  /// Slike artikala jedne smjene, po artiklu; samo one koje su već na uređaju.
  Future<Map<String, Uint8List>> lineImages(String shiftId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT l.item_id, im.data
      FROM shift_lines l
      JOIN items i ON i.id = l.item_id
      JOIN images im ON im.id = i.image_id
      WHERE l.shift_id = ?
      ''',
      [shiftId],
    );
    return {
      for (final r in rows) r['item_id'] as String: r['data'] as Uint8List,
    };
  }

  /// Smjene radnika koje imaju izmjene neposlane na server, sa revizijom u trenutku čitanja.
  Future<Map<String, int>> dirtyShifts(String workerId) async {
    final rows = await _db.query(
      'shifts',
      columns: ['id', 'dirty'],
      where: 'dirty > 0 AND worker_id = ?',
      whereArgs: [workerId],
    );
    return {for (final r in rows) r['id'] as String: r['dirty'] as int};
  }

  /// Označava smjenu poslanom, osim ako je u međuvremenu opet mijenjana.
  Future<void> markClean(String shiftId, int revision) async {
    await _db.update(
      'shifts',
      {'dirty': 0},
      where: 'id = ? AND dirty = ?',
      whereArgs: [shiftId, revision],
    );
    notifyListeners();
  }

  Future<bool> hasUnsent() async {
    final rows = await _db.query('shifts', where: 'dirty > 0', limit: 1);
    return rows.isNotEmpty;
  }
}
