import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../common.dart';
import 'item_tile.dart';
import 'number_pad.dart';
import 'scope.dart';

/// Okvir zajednički za ULAZ, RASHOD i STANJE: cijela traka i donje dugme su u boji unosa.
class ModeScaffold extends StatelessWidget {
  const ModeScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.body,
    this.bottom,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: color,
        foregroundColor: Colors.white,
        toolbarHeight: 76,
        titleSpacing: 0,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Icon(
                icon,
                size: 30,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
      body: body,
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: bottom,
              ),
            ),
    );
  }
}

/// Glavno dugme na dnu ekrana unosa, u boji tog unosa.
class ModeButton extends StatelessWidget {
  const ModeButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: color),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// Mreža kvadratića artikala; sa slikama su kvadratići viši.
SliverGridDelegate itemGridDelegate({required bool withImages}) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: withImages ? 0.86 : 1.12,
    );

class _UlazData {
  const _UlazData(this.lines, this.draft, this.images);

  final List<ObracunLine> lines;
  final Map<String, int> draft;

  /// Slike artikala po artiklu.
  final Map<String, Uint8List> images;
}

String _signed(int qty) => qty > 0 ? '+$qty' : '$qty';

/// Unos primljene robe. Jedan ulaz je jedna dostava: unese se, pa zaključi.
class UlazScreen extends StatelessWidget {
  const UlazScreen({super.key, required this.shiftId});

  final String shiftId;

  Future<void> _edit(
    BuildContext context,
    ObracunLine line,
    int? current,
  ) async {
    final result = await showQtyPad(
      context,
      mode: 'Primljena količina',
      itemName: line.name,
      color: ModeColors.ulaz,
      hint: 'Za povrat ili ispravku unesite minus (+/−)',
      initial: current,
      allowNegative: true,
    );
    if (result == null || !context.mounted) return;
    await guard(
      context,
      () => RepoScope.of(
        context,
      ).setDraftReceiptQty(shiftId, line.itemId, result.value),
    );
  }

  Future<void> _close(BuildContext context, _UlazData data) async {
    final entered = data.lines
        .where((l) => data.draft.containsKey(l.itemId))
        .toList();
    final ok = await confirm(
      context,
      title: 'Zaključiti ulaz?',
      action: 'Zaključi ulaz',
      color: ModeColors.ulaz,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in entered)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.name),
                  Text(
                    _signed(data.draft[l.itemId]!),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const Text('Nakon zaključenja se ovaj ulaz ne može mijenjati.'),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    final closed = await guard(
      context,
      () => RepoScope.of(context).closeDraftReceipt(shiftId),
    );
    if (closed && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Loader<_UlazData>(
      load: (repo) async => _UlazData(
        (await repo.obracunForShift(
          shiftId,
        )).lines.where((l) => l.kind == ItemKind.stock).toList(),
        await repo.draftReceipt(shiftId),
        await repo.lineImages(shiftId),
      ),
      builder: (context, data) => ModeScaffold(
        title: 'ULAZ',
        subtitle: 'Roba koja je stigla',
        icon: Icons.local_shipping_outlined,
        color: ModeColors.ulaz,
        bottom: ModeButton(
          color: ModeColors.ulaz,
          onPressed: data.draft.isEmpty ? null : () => _close(context, data),
          label: data.draft.isEmpty
              ? 'Dodirnite artikal koji je stigao'
              : 'Zaključi ulaz (${data.draft.length})',
        ),
        body: RefreshIndicator(
          color: ModeColors.ulaz,
          onRefresh: () => refreshWithMessage(context, quiet: true),
          child: GridView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: itemGridDelegate(withImages: data.images.isNotEmpty),
            children: [
              for (final l in data.lines)
                ItemTile(
                  name: l.name,
                  image: data.images[l.itemId],
                  color: ModeColors.ulaz,
                  value: data.draft.containsKey(l.itemId)
                      ? _signed(data.draft[l.itemId]!)
                      : null,
                  note: l.received != 0
                      ? 'ranije ${_signed(l.received)}'
                      : null,
                  onTap: () => _edit(context, l, data.draft[l.itemId]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
