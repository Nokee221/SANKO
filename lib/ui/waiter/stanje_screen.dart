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

/// Prodano u smjeni, po artiklu. Kad je uneseno sve, slijedi predaja i zaključenje.
/// Zatvara se sa `true` ako je smjena zaključena.
class StanjeScreen extends StatefulWidget {
  const StanjeScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  State<StanjeScreen> createState() => _StanjeScreenState();
}

class _StanjeScreenState extends State<StanjeScreen> {
  bool _onlyMissing = false;

  Future<void> _edit(ObracunLine line) async {
    final counter = line.kind == ItemKind.counter;
    final result = await showQtyPad(
      context,
      mode: 'Prodano',
      itemName: line.name,
      color: ModeColors.stanje,
      hint:
          '${fmtKm(line.price)} po komadu · '
          '${counter ? 'brojač na početku ${line.opening}' : 'na šanku ${line.total}'}',
      initial: line.consumed,
    );
    if (result == null || !mounted) return;
    await guard(
      context,
      () => RepoScope.of(
        context,
      ).setSoldQty(widget.shiftId, line.itemId, result.value),
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
          subtitle: 'Koliko je prodano u smjeni',
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
                            backgroundColor: SankoColors.line,
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
                      backgroundColor: Colors.white,
                      selectedColor: ModeColors.stanje.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: _onlyMissing
                            ? ModeColors.stanje
                            : SankoColors.line,
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
                          value: l.consumed?.toString(),
                          note: l.kind == ItemKind.counter ? 'brojač' : null,
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
