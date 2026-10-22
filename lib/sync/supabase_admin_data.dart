import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/admin_data.dart';
import '../data/demo_items.dart';
import '../data/errors.dart';
import '../data/models.dart';
import '../data/orders.dart';
import '../domain/obracun.dart';
import '../domain/report.dart';
import '../domain/stats.dart';
import 'supabase_errors.dart';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Podaci jednog lokala direktno iz Supabasea. Admin panel radi samo sa mrežom.
class SupabaseAdminData extends ChangeNotifier implements AdminData {
  SupabaseAdminData(this._client, this.venueId) {
    // Kad telefon pošalje smjenu, prikaz se sam osvježi.
    _channel = _client
        .channel('shifts-$venueId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'venue_id',
            value: venueId,
          ),
          // Zaključena smjena mijenja i statistiku, pa se ona ponovo učitava.
          callback: (_) {
            _stats.clear();
            notifyListeners();
          },
        )
        .subscribe();
  }

  final SupabaseClient _client;
  final String venueId;
  late final RealtimeChannel _channel;

  @override
  void dispose() {
    _client.removeChannel(_channel);
    super.dispose();
  }

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await supabaseCall(call);
    } on OfflineException {
      throw SankoException('Nema veze sa serverom. Provjerite internet.');
    }
  }

  Future<void> _write(Future<void> Function() call) async {
    await _call(call);
    notifyListeners();
  }

  @override
  void refresh() {
    _catalog = null;
    _stats.clear();
    notifyListeners();
  }

  // Katalog se rijetko mijenja, pa se učitava jednom i pamti do sljedećeg osvježavanja.
  List<CatalogImage>? _catalog;

  /// Ako katalog nije dostupan, artikli i dalje rade, samo bez slika.
  @override
  Future<List<CatalogImage>> catalogImages() async {
    final cached = _catalog;
    if (cached != null) return cached;
    try {
      final loaded = await _call(() async {
        final rows = await _client
            .from('catalog_images')
            .select('id, name, data')
            .order('name', ascending: true);
        return [
          for (final r in rows)
            CatalogImage(
              id: r['id'] as String,
              name: r['name'] as String,
              bytes: base64Decode(r['data'] as String),
            ),
        ];
      });
      _catalog = loaded;
      return loaded;
    } on SankoException {
      return const [];
    }
  }

  @override
  Future<List<Worker>> workers() => _call(() async {
    final rows = await _client
        .from('workers')
        .select()
        .eq('venue_id', venueId)
        .eq('active', true)
        .order('name', ascending: true);
    return [
      for (final r in rows)
        Worker(
          id: r['id'] as String,
          name: r['name'] as String,
          role: WorkerRole.parse(r['role']),
        ),
    ];
  });

  @override
  Future<void> addWorker({
    required String name,
    required String pin,
    WorkerRole role = WorkerRole.konobar,
  }) => _write(
    () => _client.rpc(
      'admin_save_worker',
      params: {
        'p_venue_id': venueId,
        'p_name': name,
        'p_pin': pin,
        'p_role': role.name,
      },
    ),
  );

  @override
  Future<void> setWorkerRole(String id, WorkerRole role) => _write(() async {
    final worker = await _client
        .from('workers')
        .select('name')
        .eq('id', id)
        .single();
    await _client.rpc(
      'admin_save_worker',
      params: {
        'p_venue_id': venueId,
        'p_name': worker['name'],
        'p_worker_id': id,
        'p_role': role.name,
      },
    );
  });

  @override
  Future<List<VenueTable>> tables() => _call(() async {
    final rows = await _client
        .from('venue_tables')
        .select('id, name')
        .eq('venue_id', venueId)
        .eq('active', true)
        .order('sort_order')
        .order('name');
    return [
      for (final r in rows)
        VenueTable(id: r['id'] as String, name: r['name'] as String),
    ];
  });

  @override
  Future<void> addTables(List<String> names) => _write(() async {
    final clean = [
      for (final n in names)
        if (n.trim().isNotEmpty) n.trim(),
    ];
    if (clean.isEmpty) throw SankoException('Unesite naziv stola.');
    final last = await _client
        .from('venue_tables')
        .select('sort_order')
        .eq('venue_id', venueId)
        .order('sort_order', ascending: false)
        .limit(1);
    var order = last.isEmpty ? 0 : last.first['sort_order'] as int;
    await _client.from('venue_tables').insert([
      for (final name in clean)
        {'venue_id': venueId, 'name': name, 'sort_order': ++order},
    ]);
  });

  @override
  Future<void> removeTable(String id) => _write(
    () => _client.from('venue_tables').update({'active': false}).eq('id', id),
  );

  @override
  Future<void> removeWorker(String id) => _write(
    () => _client.rpc('admin_remove_worker', params: {'p_worker_id': id}),
  );

  @override
  Future<List<Item>> items() => _call(() async {
    final rows = await _client
        .from('items')
        .select()
        .eq('venue_id', venueId)
        .eq('active', true)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return rows.map(Item.fromRemote).toList();
  });

  @override
  Future<bool> itemHasHistory(String id) => _call(() async {
    final rows = await _client
        .from('shift_lines')
        .select('item_id')
        .eq('item_id', id)
        .limit(1);
    return rows.isNotEmpty;
  });

  @override
  Future<void> addItem({
    required String name,
    required ItemKind kind,
    required int price,
    int initialQty = 0,
    String? imageId,
    int? minQty,
    int? parQty,
  }) {
    if (name.trim().isEmpty) throw SankoException('Unesite naziv artikla.');
    return _write(
      () => _client.from('items').insert({
        'venue_id': venueId,
        'name': name.trim(),
        'kind': kind.name,
        'price': price,
        'initial_qty': initialQty,
        'image_id': imageId,
        // Starija baza nema minimum; bez njega upis i dalje prolazi.
        'min_qty': ?minQty,
        'par_qty': ?parQty,
      }),
    );
  }

  // Redoslijed dodjeljuje okidač u bazi, red po red iza postojećih artikala.
  @override
  Future<void> addItems(List<NewItem> items) {
    if (items.any((i) => i.name.trim().isEmpty)) {
      throw SankoException('Unesite naziv artikla.');
    }
    return _write(
      () => _client.from('items').insert([
        for (final i in items)
          {
            'venue_id': venueId,
            'name': i.name.trim(),
            'kind': i.kind.name,
            'price': i.price,
            'initial_qty': i.initialQty,
            'image_id': i.imageId,
          },
      ]),
    );
  }

  /// Nova cijena i naziv važe od sljedeće smjene.
  @override
  Future<void> updateItem(Item item) {
    if (item.name.trim().isEmpty) {
      throw SankoException('Unesite naziv artikla.');
    }
    return _write(
      () => _client
          .from('items')
          .update({
            'name': item.name.trim(),
            'price': item.price,
            'initial_qty': item.initialQty,
            'image_id': item.imageId,
            'min_qty': item.minQty,
            'par_qty': item.parQty,
          })
          .eq('id', item.id),
    );
  }

  @override
  Future<void> removeItem(String id) => _write(
    () => _client.from('items').update({'active': false}).eq('id', id),
  );

  @override
  Future<void> seedDemoItems() => _write(
    () => _client.from('items').insert([
      for (final (i, (name, kind, price, qty)) in demoItems.indexed)
        {
          'venue_id': venueId,
          'name': name,
          'kind': kind.name,
          'price': price,
          'initial_qty': qty,
          'sort_order': i + 1,
        },
    ]),
  );

  @override
  Future<List<Shift>> shiftsOn(DateTime day) => _call(() async {
    final rows = await _client
        .from('shifts')
        .select()
        .eq('venue_id', venueId)
        .eq('business_date', _dateKey(day))
        .order('seq', ascending: true);
    return rows.map(Shift.fromRemote).toList();
  });

  /// U primljeno ulaze samo zaključeni ulazi.
  @override
  Future<Obracun> obracunForShift(String shiftId) => _call(() async {
    // Tri upita idu istovremeno, da se obračun brže učita.
    final linesQuery = _client
        .from('shift_lines')
        .select()
        .eq('shift_id', shiftId)
        .order('sort_order', ascending: true)
        .order('item_name', ascending: true);
    final receiptsQuery = _client
        .from('receipts')
        .select('closed_at, receipt_lines(item_id, qty)')
        .eq('shift_id', shiftId)
        .not('closed_at', 'is', null);
    // Greška ovih upita se hvata niže, kad se sačekaju; ovdje ne smije ostati neuhvaćena.
    final spentQuery = expenses(shiftId)..ignore();
    final handoverQuery = _handover(shiftId)..ignore();
    final [lines, receipts] = await Future.wait([linesQuery, receiptsQuery]);
    final received = <String, int>{};
    for (final r in receipts) {
      for (final l in r['receipt_lines'] as List) {
        received.update(
          l['item_id'] as String,
          (v) => v + (l['qty'] as int),
          ifAbsent: () => l['qty'] as int,
        );
      }
    }
    final spent = await spentQuery;
    final handover = await handoverQuery;
    return Obracun(
      kitchen: handover['kitchen'] as int? ?? 0,
      cash: handover['cash'] as int?,
      card: handover['card'] as int?,
      lines: [
        for (final l in lines)
          ObracunLine.forShift(
            itemId: l['item_id'] as String,
            name: l['item_name'] as String,
            kind: ItemKind.values.byName(l['kind'] as String),
            price: l['price'] as int,
            opening: l['opening_qty'] as int,
            received: received[l['item_id']] ?? 0,
            closing: l['closing_qty'] as int?,
          ),
      ],
      expenses: spent.fold(0, (sum, e) => sum + e.amount),
    );
  });

  /// Kuhinja i predaja smjene. Starija baza ih nema; obračun tada radi bez njih.
  Future<Map<String, dynamic>> _handover(String shiftId) async {
    try {
      return await _call(
        () => _client
            .from('shifts')
            .select('kitchen, cash, card')
            .eq('id', shiftId)
            .single(),
      );
    } on SankoException {
      return const {};
    }
  }

  @override
  Future<List<Expense>> expenses(String shiftId) => _call(() async {
    final rows = await _client
        .from('expenses')
        .select()
        .eq('shift_id', shiftId)
        .order('created_at', ascending: true);
    return rows.map(Expense.fromRemote).toList();
  });

  @override
  Future<void> adminCloseShift(
    String shiftId,
    Map<String, int> counts, {
    Handover? handover,
  }) => _write(
    () => _client.rpc(
      'admin_close_shift',
      params: {
        'p_shift_id': shiftId,
        'p_counts': [
          for (final e in counts.entries)
            {'item_id': e.key, 'closing_qty': e.value},
        ],
        if (handover != null)
          'p_handover': {
            'kitchen': handover.kitchen,
            'cash': handover.cash,
            'card': handover.card,
          },
      },
    ),
  );

  @override
  Future<void> setHandover(String shiftId, Handover handover, {String? note}) =>
      _write(
        () => _client.rpc(
          'admin_set_handover',
          params: {
            'p_shift_id': shiftId,
            'p_kitchen': handover.kitchen,
            'p_cash': handover.cash,
            'p_card': handover.card,
            'p_note': note,
          },
        ),
      );

  @override
  Future<List<ShiftSummary>> shiftSummaries(DateTime from, DateTime to) async {
    final rows = await _call(
      () => _client.rpc(
        'admin_shift_summaries',
        params: {
          'p_venue_id': venueId,
          'p_from': _dateKey(from),
          'p_to': _dateKey(to),
        },
      ),
    );
    return [
      for (final r in rows as List)
        ShiftSummary.fromJson(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<TelegramStatus> telegramStatus() async {
    final r = await _call(
      () =>
          _client.rpc('admin_telegram_status', params: {'p_venue_id': venueId}),
    );
    return TelegramStatus.fromJson(r as Map<String, dynamic>);
  }

  @override
  Future<String> telegramLink() async {
    final url = await _call(
      () => _client.rpc('admin_telegram_link', params: {'p_venue_id': venueId}),
    );
    return url as String;
  }

  @override
  Future<void> telegramUnlink() => _write(
    () => _client.rpc('admin_telegram_unlink', params: {'p_venue_id': venueId}),
  );

  // Istorija se ne mijenja dok se gleda obračun, pa se pamti do sljedećeg osvježavanja.
  final _stats = <String, List<StatLine>>{};

  @override
  Future<List<StatLine>> statLines(DateTime from, DateTime to) async {
    final key = '${_dateKey(from)}/${_dateKey(to)}';
    final cached = _stats[key];
    if (cached != null) return cached;
    final rows = await _call(
      () => _client.rpc(
        'admin_stat_lines',
        params: {
          'p_venue_id': venueId,
          'p_from': _dateKey(from),
          'p_to': _dateKey(to),
        },
      ),
    );
    return _stats[key] = [
      for (final r in rows as List)
        StatLine.fromJson(r as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> correctShift(
    String shiftId,
    List<ItemCorrection> changes, {
    String? note,
  }) => _write(() async {
    await _client.rpc(
      'admin_correct_shift',
      params: {
        'p_shift_id': shiftId,
        'p_note': note,
        'p_changes': [
          for (final c in changes)
            {
              'item_id': c.itemId,
              if (c.closing != null) 'closing_qty': c.closing,
              if (c.received != null) 'received': c.received,
            },
        ],
      },
    );
    // Ispravka mijenja istoriju, pa prosjeci moraju ponovo da se učitaju.
    _stats.clear();
  });

  @override
  Future<List<ShiftCorrection>> corrections(List<String> shiftIds) async {
    if (shiftIds.isEmpty) return const [];
    // Prije pokretanja skripte za ispravke tabela ne postoji; obračun i dalje radi.
    try {
      final rows = await _call(
        () => _client
            .from('shift_corrections')
            .select()
            .inFilter('shift_id', shiftIds)
            .order('corrected_at', ascending: true),
      );
      return rows.map(ShiftCorrection.fromRemote).toList();
    } on SankoException {
      return const [];
    }
  }

  /// Bez skripte za zalihu (starija baza) upozorenja jednostavno nema.
  @override
  Future<List<StockLevel>> currentStock() async {
    try {
      final rows = await _call(
        () =>
            _client.rpc('admin_current_stock', params: {'p_venue_id': venueId}),
      );
      return [
        for (final r in rows as List)
          StockLevel.fromJson(r as Map<String, dynamic>),
      ];
    } on SankoException {
      return const [];
    }
  }
}
