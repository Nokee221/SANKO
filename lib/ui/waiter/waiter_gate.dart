import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/errors.dart';
import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'rashod_screen.dart';
import 'scope.dart';
import 'stanje_screen.dart';
import 'ulaz_screen.dart';

/// Nakon prijave odlučuje šta konobar vidi: početak smjene, svoju otvorenu smjenu,
/// obavijest da je tuđa smjena još otvorena, ili obračun smjene koju je upravo zaključio.
class WaiterGate extends StatefulWidget {
  const WaiterGate({super.key, required this.worker});

  final Worker worker;

  @override
  State<WaiterGate> createState() => _WaiterGateState();
}

class _WaiterGateState extends State<WaiterGate> {
  String? _closedShiftId;

  @override
  Widget build(BuildContext context) {
    if (_closedShiftId != null) return _Summary(shiftId: _closedShiftId!);

    return Loader<Shift?>(
      load: (repo) => repo.openShift(),
      builder: (context, shift) {
        if (shift == null) return _StartShift(worker: widget.worker);
        if (shift.workerId != widget.worker.id) return _Blocked(shift: shift);
        return _Home(
          shift: shift,
          onClosed: () => setState(() => _closedShiftId = shift.id),
        );
      },
    );
  }
}

/// Tamna ploča na vrhu ekrana, sa zaobljenim donjim rubom.
class _DarkPanel extends StatelessWidget {
  const _DarkPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Ploča je ispod statusne trake, pa njene ikone trebaju biti svijetle.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: _panel(),
    );
  }

  Widget _panel() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: SankoColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 12, 24),
          child: child,
        ),
      ),
    );
  }
}

/// Zaglavlje sa lokalom i imenom prijavljenog radnika; ispod idu npr. podaci o smjeni.
class WaiterHeader extends StatelessWidget {
  const WaiterHeader({super.key, required this.name, this.children = const []});

  final String name;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final venue = SyncScope.of(context).venueName;
    return _DarkPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  venue ?? 'Šanko',
                  style: const TextStyle(
                    color: SankoColors.brass,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Osvježi',
                icon: const Icon(Icons.refresh),
                color: Colors.white70,
                onPressed: () => refreshWithMessage(context),
              ),
              IconButton(
                tooltip: 'Odjava',
                icon: const Icon(Icons.logout),
                color: Colors.white70,
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              ),
            ],
          ),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// Jesu li unosi stigli na server.
class _SyncPill extends StatelessWidget {
  const _SyncPill();

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    final (color, label) = sync.lastError != null
        ? (SankoColors.failed, 'Server je odbio slanje: ${sync.lastError}')
        : sync.hasUnsent
        ? (SankoColors.waiting, 'Čeka slanje na server')
        : (SankoColors.ok, 'Sve je poslano na server');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartShift extends StatelessWidget {
  const _StartShift({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          WaiterHeader(
            name: worker.name,
            children: const [
              SizedBox(height: 10),
              Text(
                'Nema otvorene smjene',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Početno stanje se preuzima iz prethodne smjene.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, color: SankoColors.ink),
                    ),
                    const SizedBox(height: 24),
                    _StartButton(worker: worker),
                    const SizedBox(height: 14),
                    const Text(
                      'Za početak smjene je potreban internet.',
                      style: TextStyle(color: SankoColors.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatefulWidget {
  const _StartButton({required this.worker});

  final Worker worker;

  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _busy = false;

  Future<void> _start() async {
    final sync = SyncScope.of(context);
    setState(() => _busy = true);
    String? error;
    try {
      await sync.startShift(widget.worker);
    } on SankoException catch (e) {
      error = e.message;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) await showError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy ? null : _start,
        child: _busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Text('Započni smjenu', style: TextStyle(fontSize: 19)),
      ),
    );
  }
}

class _Blocked extends StatelessWidget {
  const _Blocked({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_clock_outlined,
                size: 52,
                color: SankoColors.muted,
              ),
              const SizedBox(height: 16),
              Text(
                'Smjenu još nije zaključio/la ${shift.workerName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nova smjena može početi tek kad se prethodna zaključi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: SankoColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData(this.obracun, this.draftItems, this.closedReceipts);

  final Obracun obracun;
  final int draftItems;
  final int closedReceipts;
}

class _Home extends StatelessWidget {
  const _Home({required this.shift, required this.onClosed});

  final Shift shift;
  final VoidCallback onClosed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          WaiterHeader(
            name: shift.workerName,
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: SankoColors.brass),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Smjena ${shift.seq}',
                      style: const TextStyle(
                        color: SankoColors.brass,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${weekdayName(shift.businessDate)}, ${fmtDate(shift.businessDate)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _SyncPill(),
            ],
          ),
          Expanded(
            child: Loader<_HomeData>(
              load: (repo) async => _HomeData(
                await repo.obracunForShift(shift.id),
                (await repo.draftReceipt(shift.id)).length,
                await repo.closedReceiptCount(shift.id),
              ),
              builder: (context, data) {
                final lines = data.obracun.lines;
                final entered = lines.where((l) => l.closing != null).length;
                final draft = data.draftItems > 0;
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Column(
                      children: [
                        ModeTile(
                          title: 'ULAZ',
                          subtitle: 'Roba koja je stigla',
                          value:
                              '${draft ? data.draftItems : data.closedReceipts}',
                          valueLabel: draft ? 'u unosu' : 'zaključeno',
                          icon: Icons.local_shipping_outlined,
                          color: ModeColors.ulaz,
                          onTap: () {
                            unawaited(SyncScope.of(context).refresh());
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UlazScreen(shiftId: shift.id),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ModeTile(
                          title: 'RASHOD',
                          subtitle: 'Novac potrošen iz kase',
                          value: fmtMoney(data.obracun.expenses),
                          valueLabel: 'KM',
                          icon: Icons.receipt_long_outlined,
                          color: ModeColors.rashod,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RashodScreen(shiftId: shift.id),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ModeTile(
                          title: 'STANJE',
                          subtitle: 'Koliko je prodano u smjeni',
                          value: '$entered/${lines.length}',
                          valueLabel: 'uneseno',
                          icon: Icons.fact_check_outlined,
                          color: ModeColors.stanje,
                          onTap: () async {
                            unawaited(SyncScope.of(context).refresh());
                            final closed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StanjeScreen(shiftId: shift.id),
                              ),
                            );
                            if (closed == true) onClosed();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Jedan od tri velika ulaza na početnoj: naziv lijevo, trenutno stanje desno.
/// Velika pločica u boji jednog dijela posla, sa brojem desno.
class ModeTile extends StatelessWidget {
  const ModeTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.value = '',
    this.valueLabel = '',
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final String valueLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(26),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                      const Spacer(),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.shiftId});

  final String shiftId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Loader<Obracun>(
        load: (repo) => repo.obracunForShift(shiftId),
        builder: (context, o) {
          final sold = o.lines.where((l) => l.consumed != 0).toList();
          return Column(
            children: [
              _DarkPanel(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Smjena zaključena',
                        style: TextStyle(
                          color: SankoColors.brass,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          fmtKm(o.total),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 46,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.5,
                            fontFeatures: tabularFigures,
                          ),
                        ),
                      ),
                      const Text(
                        'za predati',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(label: 'Šank', value: fmtKm(o.sank)),
                          ),
                          Expanded(
                            child: _Stat(
                              label: 'Kuhinja',
                              value: fmtKm(o.kitchen),
                            ),
                          ),
                          Expanded(
                            child: _Stat(
                              label: 'Rashod',
                              value: fmtKm(o.expenses),
                            ),
                          ),
                        ],
                      ),
                      if (o.difference case final difference?) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                label: 'Predano',
                                value: fmtKm(o.handedOver!),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: _Stat(
                                label: difference < 0
                                    ? 'Manjak'
                                    : difference > 0
                                    ? 'Višak'
                                    : 'Razlika',
                                value: difference == 0
                                    ? 'nema'
                                    : fmtKm(difference.abs()),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      const _SyncPill(),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (sold.isNotEmpty)
                      Card(
                        child: Column(
                          children: [
                            for (final (i, l) in sold.indexed) ...[
                              if (i > 0)
                                const Divider(indent: 16, endIndent: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l.name,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${l.consumed} × ${fmtMoney(l.price)}',
                                            style: const TextStyle(
                                              color: SankoColors.muted,
                                              fontSize: 13,
                                              fontFeatures: tabularFigures,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      fmtMoney(l.amount!),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: tabularFigures,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    height: 58,
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.popUntil(context, (r) => r.isFirst),
                      child: const Text('Odjava'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Razmak do susjedne kolone, i kad iznos ispuni svoju širinu.
    return Padding(padding: const EdgeInsets.only(right: 12), child: _column());
  }

  Widget _column() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}
