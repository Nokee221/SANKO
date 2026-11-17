import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/errors.dart';
import '../../data/models.dart';
import '../../data/orders.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'scope.dart';
import 'waiter_gate.dart';

/// Narudžba koja čeka duže od ovoga se ističe crveno.
const lateAfter = Duration(minutes: 5);

/// Koliko dugo stoji obavještenje o novoj narudžbi.
const arrivedFor = Duration(seconds: 5);

/// Telefon na šanku: narudžbe stižu same, najstarije gore. Tap otvara narudžbu,
/// povlačenje udesno je označava kao gotovu.
class SankScreen extends StatefulWidget {
  const SankScreen({
    super.key,
    required this.worker,
    this.pollEvery = const Duration(seconds: 4),
  });

  final Worker worker;
  final Duration pollEvery;

  @override
  State<SankScreen> createState() => _SankScreenState();
}

class _SankScreenState extends State<SankScreen> {
  List<Order>? _orders;
  String? _error;
  Timer? _timer;
  bool _loading = false;

  /// Otvorene kartice.
  final Set<String> _expanded = {};

  /// Narudžbe već viđene na ekranu, da se zvuk pusti samo za nove.
  final Set<String> _seen = {};

  /// Povučene narudžbe dok server ne potvrdi; ne vraćaju se na listu pri osvježavanju.
  final Set<String> _completing = {};

  /// Zadnja pristigla narudžba, za obavještenje na vrhu ekrana; null kad je skriveno.
  Order? _arrived;
  bool _showArrived = false;
  Timer? _arrivedTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(widget.pollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _arrivedTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    _loading = true;
    try {
      final orders = await SyncScope.of(
        context,
      ).orders(widget.worker, mine: false);
      if (!mounted) return;
      final fresh = orders.where((o) => !_seen.contains(o.id)).toList();
      if (_orders != null && fresh.isNotEmpty) {
        unawaited(HapticFeedback.heavyImpact());
        unawaited(SystemSound.play(SystemSoundType.alert));
        _announce(fresh.last, more: fresh.length - 1);
      }
      _seen.addAll(fresh.map((o) => o.id));
      setState(() {
        _orders = orders;
        _error = null;
      });
    } on SankoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _loading = false;
    }
  }

  int _arrivedMore = 0;

  /// Obavještenje sklizne odozgo i samo se skloni nakon nekoliko sekundi.
  void _announce(Order order, {int more = 0}) {
    _arrivedTimer?.cancel();
    setState(() {
      _arrived = order;
      _arrivedMore = more;
      _showArrived = true;
    });
    _arrivedTimer = Timer(arrivedFor, _hideArrived);
  }

  void _hideArrived() {
    _arrivedTimer?.cancel();
    if (mounted) setState(() => _showArrived = false);
  }

  /// Tap na obavještenje otvara narudžbu.
  void _openArrived() {
    final order = _arrived;
    _hideArrived();
    if (order != null) setState(() => _expanded.add(order.id));
  }

  Future<void> _complete(Order order) async {
    final sync = SyncScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _completing.add(order.id));
    try {
      await sync.setOrderDone(widget.worker, order.id, done: true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Gotovo: ${order.title}'),
            action: SnackBarAction(
              label: 'Poništi',
              onPressed: () => _undo(order),
            ),
          ),
        );
    } on SankoException catch (e) {
      if (mounted) await showError(context, e.message);
    } finally {
      if (mounted) setState(() => _completing.remove(order.id));
      await _load();
    }
  }

  Future<void> _undo(Order order) async {
    final sync = SyncScope.of(context);
    try {
      await sync.setOrderDone(widget.worker, order.id, done: false);
    } on SankoException catch (e) {
      if (mounted) await showError(context, e.message);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final orders = [
      for (final o in _orders ?? const <Order>[])
        if (!_completing.contains(o.id)) o,
    ];
    return Scaffold(
      body: Stack(
        children: [
          _list(orders),
          _ArrivedBanner(
            order: _arrived,
            more: _arrivedMore,
            visible: _showArrived,
            onTap: _openArrived,
            onDismiss: _hideArrived,
          ),
        ],
      ),
    );
  }

  Widget _list(List<Order> orders) {
    return Column(
      children: [
        WaiterHeader(
          name: widget.worker.name,
          children: [
            const SizedBox(height: 6),
            Text(
              _orders == null
                  ? 'Šank · učitavam narudžbe'
                  : orders.isEmpty
                  ? 'Šank · nema narudžbi na čekanju'
                  : 'Šank · ${orders.length} '
                        '${plural(orders.length, 'narudžba čeka', 'narudžbe čekaju', 'narudžbi čeka')}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: SankoColors.failed.withValues(alpha: 0.2),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(_error!, style: const TextStyle(fontSize: 15)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _orders == null
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator()),
                    ],
                  )
                : orders.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Icon(
                        Icons.local_bar_outlined,
                        size: 56,
                        color: WaiterColors.muted,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Nove narudžbe se pojave same.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          color: WaiterColors.muted,
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      for (final o in orders)
                        _OrderCard(
                          key: ValueKey(o.id),
                          order: o,
                          expanded: _expanded.contains(o.id),
                          onToggle: () => setState(() {
                            if (!_expanded.remove(o.id)) _expanded.add(o.id);
                          }),
                          onDone: () => _complete(o),
                        ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Tap otvara narudžbu, povlačenje udesno je završava.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: WaiterColors.muted),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Obavještenje o novoj narudžbi: sklizne odozgo preko zaglavlja. Tap je otvara,
/// povlačenje nagore ga sklanja.
class _ArrivedBanner extends StatelessWidget {
  const _ArrivedBanner({
    required this.order,
    required this.more,
    required this.visible,
    required this.onTap,
    required this.onDismiss,
  });

  final Order? order;
  final int more;
  final bool visible;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final order = this.order;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, -1.6),
          duration: const Duration(milliseconds: 350),
          curve: visible ? Curves.easeOutBack : Curves.easeIn,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: order == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: GestureDetector(
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) < 0) onDismiss();
                      },
                      child: Material(
                        color: Colors.white,
                        elevation: 12,
                        shadowColor: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: onTap,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: SankoColors.brass.withValues(alpha: 0.8),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: SankoColors.brass,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active,
                                    color: SankoColors.navy,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        more > 0
                                            ? 'Nove narudžbe · ${order.title} i još $more'
                                            : 'Nova narudžba · ${order.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: SankoColors.ink,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        order.lines
                                            .map((l) => '${l.qty}× ${l.label}')
                                            .join(', '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: SankoColors.muted,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  order.workerName,
                                  style: const TextStyle(
                                    color: WaiterColors.brassText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    super.key,
    required this.order,
    required this.expanded,
    required this.onToggle,
    required this.onDone,
  });

  final Order order;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final waited = DateTime.now().difference(order.createdAt);
    final late = waited >= lateAfter;
    final minutes = waited.inMinutes;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('done-${order.id}'),
        direction: DismissDirection.startToEnd,
        onDismissed: (_) => onDone(),
        background: Container(
          decoration: BoxDecoration(
            color: ModeColors.ulaz,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'Gotovo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        child: Material(
          color: WaiterColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: late ? ModeColors.rashod : WaiterColors.line,
                  width: late ? 2 : 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: WaiterColors.text,
                          ),
                        ),
                      ),
                      Text(
                        minutes < 1 ? 'upravo' : 'prije $minutes min',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: late ? FontWeight.w800 : FontWeight.w500,
                          color: late ? ModeColors.rashod : WaiterColors.muted,
                        ),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: WaiterColors.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${order.workerName} · ${order.itemCount} '
                    '${plural(order.itemCount, 'artikal', 'artikla', 'artikala')}'
                    '${order.note != null ? ' · napomena' : ''}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: WaiterColors.muted,
                    ),
                  ),
                  if (expanded) ...[
                    const Divider(height: 20),
                    for (final l in order.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${l.qty}×',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: WaiterColors.brassText,
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.name,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  // Izbor (npr. "Duža, Sa mlijekom") ispod naziva.
                                  if (l.variant.isNotEmpty)
                                    Text(
                                      l.variant,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: ModeColors.narudzba,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (order.note != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: WaiterColors.brass.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          order.note!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
