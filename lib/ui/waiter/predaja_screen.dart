import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'scope.dart';
import 'ulaz_screen.dart';

/// Zadnji korak smjene: kuhinja i novac koji konobar predaje. Aplikacija odmah
/// pokazuje manjak ili višak. Zatvara se sa `true` kad je smjena zaključena.
class PredajaScreen extends StatefulWidget {
  const PredajaScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  State<PredajaScreen> createState() => _PredajaScreenState();
}

class _PredajaScreenState extends State<PredajaScreen> {
  final _kitchen = TextEditingController();
  final _cash = TextEditingController();
  final _card = TextEditingController();

  @override
  void dispose() {
    _kitchen.dispose();
    _cash.dispose();
    _card.dispose();
    super.dispose();
  }

  /// Prazno polje je nula; null kad iznos nije ispravan.
  int? _amount(TextEditingController c) =>
      c.text.trim().isEmpty ? 0 : parseMoney(c.text.replaceAll(' ', ''));

  /// Predaja sa trenutno unesenim iznosima; null dok gotovina nije unesena ili neki iznos ne valja.
  Handover? get _handover {
    final kitchen = _amount(_kitchen);
    final card = _amount(_card);
    final cash = _cash.text.trim().isEmpty ? null : _amount(_cash);
    if (kitchen == null || card == null || cash == null) return null;
    return Handover(kitchen: kitchen, cash: cash, card: card);
  }

  Future<void> _close(Obracun obracun, Handover handover) async {
    final result = obracun.withHandover(
      kitchen: handover.kitchen,
      cash: handover.cash,
      card: handover.card,
    );
    final difference = result.difference!;
    final anomalies = obracun.lines.where((l) => l.hasAnomaly).toList();
    final ok = await confirm(
      context,
      title: 'Zaključiti smjenu?',
      action: 'Zaključi smjenu',
      color: ModeColors.stanje,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Za predati: ${fmtKm(result.total)}'),
          Text('Predajete: ${fmtKm(result.handedOver!)}'),
          if (difference != 0) ...[
            const SizedBox(height: 8),
            Text(
              difference < 0
                  ? 'Manjak ${fmtKm(-difference)} vidi i gazda.'
                  : 'Višak ${fmtKm(difference)} vidi i gazda.',
              style: TextStyle(
                color: difference < 0
                    ? Theme.of(context).colorScheme.error
                    : SankoColors.ink,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          if (anomalies.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Prebrojano je više nego što je bilo: '
              '${anomalies.map((l) => l.name).join(', ')}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Nakon zaključenja se smjena više ne može mijenjati.'),
        ],
      ),
    );
    if (!ok || !mounted) return;
    final closed = await guard(
      context,
      () =>
          RepoScope.of(context).closeShift(widget.shiftId, handover: handover),
    );
    if (closed && mounted) Navigator.pop(context, true);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        fontFeatures: tabularFigures,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: 'KM',
        fillColor: Colors.white,
        errorText: _amount(controller) == null
            ? 'Neispravan iznos. Primjer: 120,50'
            : null,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Loader<Obracun>(
      load: (repo) => repo.obracunForShift(widget.shiftId),
      builder: (context, obracun) {
        final handover = _handover;
        final kitchen = _amount(_kitchen) ?? 0;
        final total = obracun.sank + kitchen - obracun.expenses;
        final difference = handover == null
            ? null
            : handover.cash + handover.card - total;
        final anomalies = obracun.lines.where((l) => l.hasAnomaly).toList();
        return ModeScaffold(
          title: 'PREDAJA',
          subtitle: 'Kuhinja i novac na kraju smjene',
          icon: Icons.payments_outlined,
          color: ModeColors.stanje,
          bottom: ModeButton(
            color: ModeColors.stanje,
            onPressed: handover == null
                ? null
                : () => _close(obracun, handover),
            label: handover != null
                ? 'Zaključi smjenu'
                : _cash.text.trim().isEmpty
                ? 'Unesite gotovinu'
                : 'Provjerite iznose',
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (anomalies.isNotEmpty) ...[
                _Note(
                  color: Theme.of(context).colorScheme.error,
                  text:
                      'Prebrojano je više nego što je bilo. Provjerite brojanje ili ULAZ: '
                      '${anomalies.map((l) => '${l.name} (bilo ${l.total}, uneseno ${l.closing})').join(', ')}.',
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    children: [
                      _Row(label: 'Šank', amount: obracun.sank),
                      const SizedBox(height: 10),
                      _field(
                        _kitchen,
                        'Kuhinja',
                        hint: '0,00',
                        autofocus: true,
                      ),
                      const SizedBox(height: 10),
                      _Row(label: 'Rashod', amount: -obracun.expenses),
                      const Divider(height: 24),
                      _Row(label: 'Za predati', amount: total, big: true),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    children: [
                      _field(_cash, 'Gotovina'),
                      const SizedBox(height: 10),
                      _field(_card, 'Kartice', hint: '0,00'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (difference != null) _Difference(difference: difference),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.amount, this.big = false});

  final String label;
  final int amount;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: big ? 17 : 15,
              fontWeight: big ? FontWeight.w700 : FontWeight.w500,
              color: big ? SankoColors.ink : SankoColors.muted,
            ),
          ),
        ),
        Text(
          fmtKm(amount),
          style: TextStyle(
            fontSize: big ? 26 : 18,
            fontWeight: big ? FontWeight.w800 : FontWeight.w700,
            fontFeatures: tabularFigures,
            color: SankoColors.ink,
          ),
        ),
      ],
    );
  }
}

/// Manjak, višak ili tačno, odmah dok konobar kuca.
class _Difference extends StatelessWidget {
  const _Difference({required this.difference});

  final int difference;

  @override
  Widget build(BuildContext context) {
    final (label, color) = difference < 0
        ? ('Manjak', Theme.of(context).colorScheme.error)
        : difference > 0
        ? ('Višak', SankoColors.waiting)
        : ('Tačno', SankoColors.ok);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (difference != 0)
            Text(
              fmtKm(difference.abs()),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
