import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../common.dart';
import '../theme.dart';
import 'item_tile.dart';
import 'number_pad.dart';
import 'scope.dart';
import 'ulaz_screen.dart';

/// Brojanje na kraju smjene. Kad je uneseno sve, smjena se zaključuje.
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
      mode: counter ? 'Stanje brojača na aparatu' : 'Prebrojano komada',
      itemName: line.name,
      color: ModeColors.stanje,
      hint: counter ? 'Prethodno stanje brojača: ${line.opening}' : null,
      initial: line.closing,
    );
    if (result == null || !mounted) return;
    await guard(
      context,
      () => RepoScope.of(
        context,
      ).setClosingQty(widget.shiftId, line.itemId, result.value),
    );
  }

  Future<void> _close(Obracun obracun) async {
    final anomalies = obracun.lines.where((l) => l.hasAnomaly).toList();
    final ok = await confirm(
      context,
      title: 'Zaključiti smjenu?',
      action: 'Zaključi smjenu',
      color: ModeColors.stanje,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (anomalies.isNotEmpty) ...[
            Text(
              'Prebrojano je više nego što je bilo. Provjerite brojanje ili ULAZ:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            for (final l in anomalies)
              Text('${l.name}: bilo ${l.total}, uneseno ${l.closing}'),
            const SizedBox(height: 12),
          ],
          const Text('Nakon zaključenja se smjena više ne može mijenjati.'),
        ],
      ),
    );
    if (!ok || !mounted) return;
    final closed = await guard(
      context,
      () => RepoScope.of(context).closeShift(widget.shiftId),
    );
    if (closed && mounted) Navigator.pop(context, true);
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
          subtitle: 'Brojanje na kraju smjene',
          icon: Icons.fact_check_outlined,
          color: ModeColors.stanje,
          bottom: ModeButton(
            color: ModeColors.stanje,
            onPressed: missing > 0 ? null : () => _close(obracun),
            label: missing > 0 ? 'Još $missing za unijeti' : 'Zaključi smjenu',
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
                            'Uneseno ${lines.length - missing} od ${lines.length}',
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
                          value: l.closing?.toString(),
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
