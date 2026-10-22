import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/errors.dart';
import '../../data/models.dart';
import '../../data/orders.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'item_tile.dart';
import 'scope.dart';
import 'ulaz_screen.dart';

/// Konobar bira sto (ako ih lokal ima), kuca artikle i šalje narudžbu na šank.
class NarudzbaScreen extends StatefulWidget {
  const NarudzbaScreen({super.key, required this.worker});

  final Worker worker;

  @override
  State<NarudzbaScreen> createState() => _NarudzbaScreenState();
}

/// Izbor "bez stola" kad lokal ima stolove.
const _noTable = VenueTable(id: '', name: 'Bez stola');

class _NarudzbaScreenState extends State<NarudzbaScreen> {
  Menu? _menu;
  Map<String, Uint8List> _images = const {};
  String? _loadError;

  VenueTable? _table;

  /// Količina po artiklu, redom kako su kucani.
  final Map<String, int> _cart = {};
  String? _note;

  /// Oznaka narudžbe se pravi jednom po korpi, pa ponovljeno slanje ne pravi duplikat.
  String _orderId = const Uuid().v4();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final (menu, images) = await SyncScope.of(context).menu(widget.worker);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _images = images;
        if (_table != null &&
            _table != _noTable &&
            !menu.tables.any((t) => t.id == _table!.id)) {
          _table = null;
        }
      });
    } on SankoException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _add(MenuItem item, int delta) {
    setState(() {
      final qty = (_cart[item.id] ?? 0) + delta;
      if (qty <= 0) {
        _cart.remove(item.id);
      } else {
        _cart[item.id] = qty;
      }
    });
  }

  void _clear() => setState(() {
    _cart.clear();
    _note = null;
    _orderId = const Uuid().v4();
  });

  Future<void> _editNote() async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _NoteDialog(initial: _note ?? ''),
    );
    if (note != null) setState(() => _note = note.trim().isEmpty ? null : note);
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final sync = SyncScope.of(context);
    setState(() => _sending = true);
    try {
      final order = await sync.placeOrder(
        widget.worker,
        NewOrder(
          id: _orderId,
          tableId: _table == null || _table == _noTable ? null : _table!.id,
          note: _note,
          quantities: Map.of(_cart),
        ),
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('Poslano na šank: ${order.title}'),
          ),
        );
      _clear();
      // Sljedeća narudžba je obično za drugi sto.
      if (_menu!.tables.isNotEmpty) setState(() => _table = null);
    } on SankoException catch (e) {
      if (mounted) await showError(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openMine() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MojeNarudzbeScreen(worker: widget.worker),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final menu = _menu;
    final pickTable = menu != null && menu.tables.isNotEmpty && _table == null;
    return PopScope(
      // Nazad iz artikala vraća na izbor stola, osim kad je korpa prazna.
      canPop: !(menu != null && menu.tables.isNotEmpty && _table != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _table = null);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: ModeColors.narudzba,
          foregroundColor: Colors.white,
          title: Text(
            pickTable ? 'Izaberite sto' : (_table?.name ?? 'Narudžba'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: 'Osvježi artikle',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _openMine,
              icon: const Icon(Icons.history),
              label: const Text('Moje'),
            ),
          ],
        ),
        body: _body(menu, pickTable),
        bottomNavigationBar: menu == null || pickTable
            ? null
            : _bottomBar(menu),
      ),
    );
  }

  Widget _body(Menu? menu, bool pickTable) {
    if (menu == null) {
      if (_loadError == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return _Message(
        text: _loadError!,
        action: FilledButton(
          onPressed: _load,
          child: const Text('Pokušaj ponovo'),
        ),
      );
    }
    if (menu.items.isEmpty) {
      return const _Message(text: 'Gazda još nije unio artikle.');
    }
    if (pickTable) return _tables(menu);
    return GridView(
      padding: const EdgeInsets.all(16),
      gridDelegate: itemGridDelegate(withImages: _images.isNotEmpty),
      children: [
        for (final item in menu.items)
          ItemTile(
            name: item.name,
            image: item.imageId == null ? null : _images[item.imageId],
            color: ModeColors.narudzba,
            value: _cart[item.id]?.toString(),
            note: fmtKm(item.price),
            onTap: () => _add(item, 1),
            onLongPress: () => _add(item, -1),
          ),
      ],
    );
  }

  Widget _tables(Menu menu) {
    return GridView(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.2,
      ),
      children: [
        for (final t in [...menu.tables, _noTable])
          Material(
            color: t == _noTable ? SankoColors.paper : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _table = t),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SankoColors.line),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                child: Text(
                  t.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: t == _noTable ? 14 : 18,
                    fontWeight: FontWeight.w800,
                    color: t == _noTable ? SankoColors.muted : SankoColors.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bottomBar(Menu menu) {
    final prices = {for (final i in menu.items) i.id: i.price};
    final count = _cart.values.fold(0, (a, b) => a + b);
    final total = _cart.entries.fold(
      0,
      (sum, e) => sum + (prices[e.key] ?? 0) * e.value,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: _editNote,
                    icon: const Icon(Icons.edit_note),
                    label: Text(
                      _note ?? 'Napomena',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  TextButton(onPressed: _clear, child: const Text('Očisti')),
              ],
            ),
            const SizedBox(height: 4),
            ModeButton(
              color: ModeColors.narudzba,
              onPressed: _cart.isEmpty || _sending ? null : _send,
              label: _cart.isEmpty
                  ? 'Tapnite artikle'
                  : _sending
                  ? 'Šaljem...'
                  : 'Naruči · $count kom · ${fmtKm(total)}',
            ),
            if (_cart.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Tap dodaje komad, dugi pritisak oduzima.',
                  style: TextStyle(color: SankoColors.muted, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Napomena za šank'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 200,
        decoration: const InputDecoration(hintText: 'npr. kafa bez šećera'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Spremi'),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: SankoColors.muted),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Narudžbe konobara od danas: šta šank još sprema, a šta je gotovo.
class MojeNarudzbeScreen extends StatefulWidget {
  const MojeNarudzbeScreen({super.key, required this.worker});

  final Worker worker;

  @override
  State<MojeNarudzbeScreen> createState() => _MojeNarudzbeScreenState();
}

class _MojeNarudzbeScreenState extends State<MojeNarudzbeScreen> {
  List<Order>? _orders;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final orders = await SyncScope.of(
        context,
      ).orders(widget.worker, mine: true);
      if (mounted) {
        setState(() {
          _orders = orders;
          _error = null;
        });
      }
    } on SankoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    final total = orders?.fold(0, (sum, o) => sum + o.total) ?? 0;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ModeColors.narudzba,
        foregroundColor: Colors.white,
        title: const Text(
          'Moje narudžbe',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: orders == null
          ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : _Message(text: _error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Text(
                    orders.isEmpty
                        ? 'Danas još nema narudžbi.'
                        : 'Danas ${orders.length} '
                              '${plural(orders.length, 'narudžba', 'narudžbe', 'narudžbi')}'
                              ' · ${fmtKm(total)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final o in orders) _MyOrderCard(order: o),
                ],
              ),
            ),
    );
  }
}

class _MyOrderCard extends StatelessWidget {
  const _MyOrderCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final (color, label) = order.isDone
        ? (ModeColors.ulaz, 'Gotovo')
        : (ModeColors.rashod, 'Šank sprema');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.title} · ${fmtTime(order.createdAt)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.lines.map((l) => '${l.qty}× ${l.name}').join(', '),
              style: const TextStyle(color: SankoColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              fmtKm(order.total),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
