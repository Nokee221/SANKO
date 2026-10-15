import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'item_import_dialog.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Unos artikala i njihovih početnih stanja.
class ItemsPage extends StatelessWidget {
  const ItemsPage({super.key});

  Future<void> _remove(BuildContext context, Item item) async {
    final ok = await confirm(
      context,
      title: 'Obrisati artikal?',
      action: 'Obriši',
      content: Text(
        '${item.name} se više neće pojavljivati u novim smjenama. Stari obračuni ostaju.',
      ),
    );
    if (ok && context.mounted) {
      await guard(context, () => AdminScope.of(context).removeItem(item.id));
    }
  }

  Future<void> _edit(
    BuildContext context,
    Item item,
    List<CatalogImage> catalog,
  ) async {
    late final bool hasHistory;
    final ok = await guard(
      context,
      () async =>
          hasHistory = await AdminScope.of(context).itemHasHistory(item.id),
    );
    if (!ok || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ItemDialog(item: item, hasHistory: hasHistory, catalog: catalog),
    );
  }

  Widget _row(
    BuildContext context,
    int index,
    Item item,
    List<CatalogImage> catalog,
  ) {
    final image = catalog.where((c) => c.id == item.imageId).firstOrNull;
    const muted = TextStyle(color: SankoColors.muted, fontSize: 14);
    // Telefon: dodir na red otvara izmjenu, a brisanje je u meniju.
    if (isCompact(context)) {
      return InkWell(
        onTap: () => _edit(context, item, catalog),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 0, 10),
          child: Row(
            children: [
              _Thumb(bytes: image?.bytes, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (item.kind == ItemKind.counter) 'brojač',
                        'početno ${item.initialQty}',
                        if (item.minQty != null) 'min ${item.minQty}',
                      ].join(' · '),
                      style: muted.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(
                fmtKm(item.price),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'Više',
                icon: const Icon(Icons.more_vert, color: SankoColors.muted),
                onSelected: (edit) => edit
                    ? _edit(context, item, catalog)
                    : _remove(context, item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: true, child: Text('Izmijeni')),
                  PopupMenuItem(value: false, child: Text('Obriši')),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 10, 8),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text('${index + 1}', style: muted)),
          _Thumb(bytes: image?.bytes, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Tag(item.kind == ItemKind.counter ? 'Brojač' : 'Zaliha'),
                if (item.minQty != null) ...[
                  const SizedBox(width: 8),
                  Tag('min ${item.minQty}'),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 190,
            child: Text(
              'Početno stanje ${item.initialQty}',
              textAlign: TextAlign.right,
              style: muted,
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              fmtKm(item.price),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Izmijeni',
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: SankoColors.muted,
            onPressed: () => _edit(context, item, catalog),
          ),
          IconButton(
            tooltip: 'Obriši',
            icon: const Icon(Icons.delete_outline, size: 20),
            color: SankoColors.muted,
            onPressed: () => _remove(context, item),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminLoader<(List<Item>, List<CatalogImage>)>(
      load: (data) async => (await data.items(), await data.catalogImages()),
      builder: (context, loaded) => _page(context, loaded.$1, loaded.$2),
    );
  }

  Widget _page(
    BuildContext context,
    List<Item> items,
    List<CatalogImage> catalog,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Artikli',
          children: [
            const Spacer(),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Uvezi iz Excela'),
                onPressed: () => importItemsFromExcel(
                  context,
                  existing: items,
                  catalog: catalog,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Novi artikal'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ItemDialog(catalog: catalog),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  text: 'Još nema artikala',
                  // Na telefonu dugmad idu jedno ispod drugog.
                  action: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Uvezi iz Excela'),
                        onPressed: () => importItemsFromExcel(
                          context,
                          existing: items,
                          catalog: catalog,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => AdminScope.of(context).seedDemoItems(),
                        child: const Text('Učitaj primjer artikala'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: pagePadding(context),
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 960),
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (final (i, item) in items.indexed) ...[
                                if (i > 0) const Divider(),
                                _row(context, i, item, catalog),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Sličica artikla; bez slike stoji neutralan kvadrat.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.bytes, required this.size});

  final Uint8List? bytes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: bytes == null
          ? Container(
              width: size,
              height: size,
              color: SankoColors.paper,
              child: Icon(
                Icons.image_outlined,
                size: size * 0.5,
                color: SankoColors.line,
              ),
            )
          : Image.memory(
              bytes!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
    );
  }
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({
    this.item,
    this.hasHistory = false,
    required this.catalog,
  });

  final List<CatalogImage> catalog;

  final Item? item;
  final bool hasHistory;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _price = TextEditingController(
    text: widget.item == null ? '' : fmtMoney(widget.item!.price),
  );
  late final _qty = TextEditingController(
    text: '${widget.item?.initialQty ?? ''}',
  );
  late final _min = TextEditingController(text: '${widget.item?.minQty ?? ''}');
  late final _par = TextEditingController(text: '${widget.item?.parQty ?? ''}');
  late ItemKind _kind = widget.item?.kind ?? ItemKind.stock;
  late String? _imageId = widget.item?.imageId;

  // Dok gazda sam ne izabere sliku, nudi se ona čiji naziv odgovara nazivu artikla.
  late bool _imagePicked = widget.item != null;

  void _onNameChanged(String name) {
    if (_imagePicked) return;
    final match = widget.catalog
        .where((c) => c.name == name.trim().toUpperCase())
        .firstOrNull;
    setState(() => _imageId = match?.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    _min.dispose();
    _par.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = parseMoney(_price.text);
    if (price == null) {
      showError(context, 'Cijena nije ispravna. Primjer: 3,50');
      return;
    }
    final qty = int.tryParse(_qty.text.trim().isEmpty ? '0' : _qty.text.trim());
    if (qty == null) {
      showError(context, 'Početno stanje mora biti cijeli broj.');
      return;
    }
    // Brojač nije zaliha i ne naručuje se.
    final counter = _kind == ItemKind.counter;
    final min = counter ? null : int.tryParse(_min.text.trim());
    final par = counter ? null : int.tryParse(_par.text.trim());
    if (par != null && min == null) {
      showError(
        context,
        'Unesite i minimum; bez njega se artikal ne naručuje.',
      );
      return;
    }
    if (par != null && par <= min!) {
      showError(context, '"Naručiti do" mora biti veće od minimuma.');
      return;
    }
    final data = AdminScope.of(context);
    final existing = widget.item;
    final saved = await guard(
      context,
      () => existing == null
          ? data.addItem(
              name: _name.text,
              kind: _kind,
              price: price,
              initialQty: qty,
              imageId: _imageId,
              minQty: min,
              parQty: par,
            )
          : data.updateItem(
              Item(
                id: existing.id,
                name: _name.text,
                kind: _kind,
                price: price,
                initialQty: qty,
                imageId: _imageId,
                minQty: min,
                parQty: par,
              ),
            ),
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final counter = _kind == ItemKind.counter;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.item == null ? 'Novi artikal' : 'Izmjena artikla'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Naziv'),
              onChanged: _onNameChanged,
            ),
            const SizedBox(height: 16),
            SegmentedButton<ItemKind>(
              // Na telefonu kraće oznake, da stanu u jedan red.
              segments: [
                ButtonSegment(
                  value: ItemKind.stock,
                  label: Text(
                    isCompact(context) ? 'Komadi' : 'Zaliha (komadi)',
                  ),
                ),
                ButtonSegment(
                  value: ItemKind.counter,
                  label: Text(isCompact(context) ? 'Brojač' : 'Brojač aparata'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: widget.item != null
                  ? null
                  : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cijena',
                suffixText: 'KM',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qty,
              enabled: !widget.hasHistory,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: counter
                    ? 'Početno stanje brojača'
                    : 'Početno stanje (komada)',
                helperMaxLines: 3,
                helperText: widget.hasHistory
                    ? 'Artikal je već bio u smjeni; stanje se vodi kroz smjene.'
                    : null,
              ),
            ),
            if (!counter) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _min,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Minimum',
                        helperMaxLines: 2,
                        helperText: 'Na ovoj zalihi ide u narudžbu',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _par,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Naručiti do',
                        helperMaxLines: 2,
                        helperText: 'Prazno: dvostruki minimum',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (widget.catalog.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Slika',
                style: TextStyle(color: SankoColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 132,
                child: GridView(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  children: [
                    for (final image in widget.catalog)
                      Tooltip(
                        message: image.name,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() {
                            _imagePicked = true;
                            _imageId = _imageId == image.id ? null : image.id;
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                width: 2,
                                color: _imageId == image.id
                                    ? SankoColors.navy
                                    : Colors.transparent,
                              ),
                            ),
                            child: _Thumb(bytes: image.bytes, size: 48),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (widget.item != null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Izmjene važe od sljedeće smjene.'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(onPressed: _save, child: const Text('Sačuvaj')),
      ],
    );
  }
}
