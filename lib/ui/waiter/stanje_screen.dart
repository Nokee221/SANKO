import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'item_tile.dart';
import 'number_pad.dart';
import 'predaja_screen.dart';
import 'scope.dart';
import 'ulaz_screen.dart';

/// Ostatak na kraju smjene, po artiklu (kafa: prodane porcije). Kad je uneseno sve, slijedi predaja i zaključenje.
/// Zatvara se sa `true` ako je smjena zaključena.
class StanjeScreen extends StatefulWidget {
  const StanjeScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  State<StanjeScreen> createState() => _StanjeScreenState();
}

class _StanjeScreenState extends State<StanjeScreen> {
  bool _onlyMissing = false;

  /// Za artikle na komad konobar broji koliko je ostalo; za kafu i nes iz aparata
  /// upisuje koliko je porcija prodano, a grami se oduzmu sami.
  Future<void> _edit(ObracunLine line) async {
    final counter = line.kind == ItemKind.counter;
    final result = await showQtyPad(
      context,
      mode: counter ? 'Prodano porcija' : 'Ostalo na šanku',
      itemName: line.name,
      color: ModeColors.stanje,
      hint: counter
          ? '${fmtKm(line.price)} po porciji · na zalihi ${fmtGrams(line.total)} '
                '(${line.portion} g po porciji)'
          : line.received == 0
          ? 'Bilo na šanku ${line.total}'
          : 'Bilo na šanku ${line.total} (${line.opening} + ulaz ${line.received})',
      initial: counter ? line.consumed : line.closing,
    );
    if (result == null || !mounted) return;
    final repo = RepoScope.of(context);
    await guard(
      context,
      () => counter
          ? repo.setSoldQty(widget.shiftId, line.itemId, result.value)
          : repo.setClosingQty(widget.shiftId, line.itemId, result.value),
    );
  }

  /// Kad je sve uneseno, ide se na predaju; tamo se smjena zaključuje.
  Future<void> _toHandover() async {
    final closed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PredajaScreen(shiftId: widget.shiftId)),
    );
    if (closed == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<(Obracun, Map<String, Uint8List>)>(
      load: (repo) async => (
        await repo.obracunForShift(widget.shiftId),
        await repo.lineImages(widget.shiftId),
      ),
      builder: (context, loaded) {
        final (obracun, images) = loaded;
        final lines = obracun.lines;
        final missing = lines.where((l) => l.closing == null).length;
        final shown = _onlyMissing
            ? lines.where((l) => l.closing == null).toList()
            : lines;
        return ModeScaffold(
          title: 'STANJE',
          subtitle: 'Koliko je ostalo na kraju smjene',
          icon: Icons.fact_check_outlined,
          color: ModeColors.stanje,
          bottom: ModeButton(
            color: ModeColors.stanje,
            onPressed: missing > 0 ? null : _toHandover,
            label: missing > 0 ? 'Još $missing za unijeti' : 'Dalje: predaja',
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Uneseno ${lines.length - missing} od ${lines.length}'
                            ' · ${fmtKm(obracun.sank)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabularFigures,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: lines.isEmpty
                                ? 0
                                : (lines.length - missing) / lines.length,
                            color: ModeColors.stanje,
                            backgroundColor: WaiterColors.raised,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilterChip(
                      label: const Text('Samo neuneseno'),
                      selected: _onlyMissing,
                      showCheckmark: false,
                      backgroundColor: WaiterColors.surface,
                      selectedColor: ModeColors.stanje.withValues(alpha: 0.3),
                      side: BorderSide(
                        color: _onlyMissing
                            ? ModeColors.stanje
                            : WaiterColors.line,
                      ),
                      shape: const StadiumBorder(),
                      onSelected: (v) => setState(() => _onlyMissing = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: ModeColors.stanje,
                  onRefresh: () => refreshWithMessage(context, quiet: true),
                  child: GridView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    gridDelegate: itemGridDelegate(
                      withImages: images.isNotEmpty,
                    ),
                    children: [
                      for (final l in shown)
                        ItemTile(
                          name: l.name,
                          image: images[l.itemId],
                          color: ModeColors.stanje,
                          value: l.kind == ItemKind.counter
                              ? l.consumed?.toString()
                              : l.closing?.toString(),
                          note: l.kind == ItemKind.counter
                              ? 'prodane porcije'
                              : null,
                          onTap: () => _edit(l),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
