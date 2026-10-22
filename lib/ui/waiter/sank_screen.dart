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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(widget.pollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      body: Column(
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
                          color: SankoColors.muted,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nove narudžbe se pojave same.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            color: SankoColors.muted,
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
                            style: TextStyle(color: SankoColors.muted),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: late ? ModeColors.rashod : SankoColors.line,
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
                            color: SankoColors.ink,
                          ),
                        ),
                      ),
                      Text(
                        minutes < 1 ? 'upravo' : 'prije $minutes min',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: late ? FontWeight.w800 : FontWeight.w500,
                          color: late ? ModeColors.rashod : SankoColors.muted,
                        ),
                      ),
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        color: SankoColors.muted,
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
                      color: SankoColors.muted,
                    ),
                  ),
                  if (expanded) ...[
                    const Divider(height: 20),
                    for (final l in order.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                '${l.qty}×',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: ModeColors.narudzba,
                                  fontFeatures: tabularFigures,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                l.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
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
                          color: SankoColors.waiting.withValues(alpha: 0.18),
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
