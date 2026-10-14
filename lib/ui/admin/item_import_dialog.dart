import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../domain/item_import.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'scope.dart';

/// Gazda bira .xlsx fajl, pregleda pročitane artikle i dodaje označene.
Future<void> importItemsFromExcel(
  BuildContext context, {
  required List<Item> existing,
  required List<CatalogImage> catalog,
}) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Excel', extensions: ['xlsx']),
    ],
  );
  if (file == null || !context.mounted) return;
  late final List<ImportedItem> found;
  final ok = await guard(
    context,
    () async => found = itemsFromXlsx(await file.readAsBytes()),
  );
  if (!ok || !context.mounted) return;
  if (found.isEmpty) {
    await showError(
      context,
      'U fajlu nisu pronađeni artikli.\n'
      'Tabela treba imati kolone "Naziv artikla" i "Cijena".',
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) =>
        _ImportDialog(found: found, existing: existing, catalog: catalog),
  );
}

class _Row {
  _Row(this.item, {required this.exists})
    : kind = item.kind,
      selected = !exists && item.price != null;

  final ImportedItem item;
  final bool exists;
  ItemKind kind;
  bool selected;

  String? get note => exists
      ? 'već postoji'
      : item.price == null
      ? 'nema cijene'
      : null;
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.found,
    required this.existing,
    required this.catalog,
  });

  final List<ImportedItem> found;
  final List<Item> existing;
  final List<CatalogImage> catalog;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final _rows = () {
    final names = {
      for (final i in widget.existing) i.name.trim().toUpperCase(),
    };
    return [
      for (final item in widget.found)
        _Row(item, exists: names.contains(item.name)),
    ];
  }();

  int get _count => _rows.where((r) => r.selected).length;

  Future<void> _save() async {
    final items = [
      for (final r in _rows)
        if (r.selected)
          NewItem(
            name: r.item.name,
            kind: r.kind,
            price: r.item.price!,
            initialQty: r.item.qty,
            imageId: widget.catalog
                .where((c) => c.name == r.item.name)
                .firstOrNull
                ?.id,
          ),
    ];
    final count = items.length;
    final saved = await guard(
      context,
      () => AdminScope.of(context).addItems(items),
    );
    if (!saved || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Dodano $count ${plural(count, 'artikal', 'artikla', 'artikala')}.',
        ),
      ),
    );
  }

  Widget _row(_Row r) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    const number = TextStyle(fontSize: 15, fontFeatures: tabularFigures);
    final price = r.item.price;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: r.selected,
            onChanged: price == null
                ? null
                : (v) => setState(() => r.selected = v ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (r.note case final note?) Text(note, style: muted),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButton<ItemKind>(
              value: r.kind,
              isDense: true,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                  value: ItemKind.stock,
                  child: Text('Zaliha (komadi)'),
                ),
                DropdownMenuItem(
                  value: ItemKind.counter,
                  child: Text('Brojač aparata'),
                ),
              ],
              onChanged: (k) => setState(() => r.kind = k!),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${r.item.qty}',
              textAlign: TextAlign.right,
              style: number,
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              price == null ? '—' : fmtKm(price),
              textAlign: TextAlign.right,
              style: number.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(color: SankoColors.muted, fontSize: 13);
    final all = _rows.where((r) => r.item.price != null && !r.exists).toList();
    final allSelected = all.isNotEmpty && all.every((r) => r.selected);
    return AlertDialog(
      title: const Text('Uvoz artikala iz Excela'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'U fajlu je ${_rows.length} '
              '${plural(_rows.length, 'artikal', 'artikla', 'artikala')}. '
              'Stanje iz tabele postaje početno stanje. '
              'Provjerite vrstu; kafa i nes s aparata se vode kao brojač.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: all.isEmpty
                      ? null
                      : (v) => setState(() {
                          for (final r in all) {
                            r.selected = v ?? false;
                          }
                        }),
                ),
                const SizedBox(width: 4),
                const Expanded(child: Text('Naziv', style: head)),
                const SizedBox(width: 170, child: Text('Vrsta', style: head)),
                const SizedBox(
                  width: 110,
                  child: Text(
                    'Stanje',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                ),
                const SizedBox(
                  width: 110,
                  child: Text(
                    'Cijena',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const Divider(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final r in _rows) _row(r)],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _count == 0 ? null : _save,
          child: Text(
            'Dodaj $_count ${plural(_count, 'artikal', 'artikla', 'artikala')}',
          ),
        ),
      ],
    );
  }
}
