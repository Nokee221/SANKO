import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../domain/report.dart';
import '../../domain/stats.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'save_file.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Lista za narudžbu: artikli čija je zaliha pala na minimum, sa predloženom količinom
/// koju gazda može promijeniti i poslati dobavljaču.
class NarudzbaPage extends StatelessWidget {
  const NarudzbaPage({super.key, this.venueName = ''});

  final String venueName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Narudžba',
          children: [
            const Spacer(),
            IconButton(
              tooltip: 'Osvježi',
              icon: const Icon(Icons.refresh),
              onPressed: () => AdminScope.of(context).refresh(),
            ),
          ],
        ),
        Expanded(
          child: AdminLoader<(List<Item>, List<OrderLine>)>(
            load: (data) async {
              final items = await data.items();
              final today = dateOnly(DateTime.now());
              final history = ItemStats.compute(
                await data.statLines(
                  today.subtract(const Duration(days: 30)),
                  today,
                ),
              );
              return (
                items,
                orderList(items, await data.currentStock(), history),
              );
            },
            builder: (context, loaded) => _OrderList(
              key: ValueKey(
                loaded.$2.map((l) => '${l.itemId}:${l.qty}').join(),
              ),
              items: loaded.$1,
              lines: loaded.$2,
              venueName: venueName,
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderList extends StatefulWidget {
  const _OrderList({
    super.key,
    required this.items,
    required this.lines,
    required this.venueName,
  });

  final List<Item> items;
  final List<OrderLine> lines;
  final String venueName;

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList> {
  late final _qty = {
    for (final l in widget.lines)
      l.itemId: TextEditingController(text: '${l.qty}'),
  };
  late final _selected = {for (final l in widget.lines) l.itemId};

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Označeni artikli sa količinom većom od nule.
  List<(String name, int qty)> get _order => [
    for (final l in widget.lines)
      if (_selected.contains(l.itemId))
        if (int.tryParse(_qty[l.itemId]!.text.trim()) case final qty?
            when qty > 0)
          (l.name, qty),
  ];

  String get _title {
    final venue = widget.venueName.isEmpty ? '' : ' – ${widget.venueName}';
    return 'Narudžba$venue, ${fmtDate(DateTime.now())}';
  }

  String get _text =>
      [_title, for (final (name, qty) in _order) '$name: $qty'].join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Narudžba je kopirana; zalijepite je u Viber ili e-mail.',
        ),
      ),
    );
  }

  /// Otvara Viber sa narudžbom; ako Viber nije instaliran, kopira je.
  Future<void> _viber() async {
    final uri = Uri.parse('viber://forward?text=${Uri.encodeComponent(_text)}');
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    // Telefon bez Vibera: meni za dijeljenje nudi WhatsApp, poruke i mail.
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await SharePlus.instance.share(ShareParams(text: _text, subject: _title));
      return;
    }
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    await showError(
      context,
      'Viber nije pronađen na ovom računaru. Narudžba je kopirana; '
      'zalijepite je u Viber poruku dobavljaču.',
    );
  }

  Future<void> _pdf() async {
    final bytes = await buildOrderPdf(title: _title, lines: _order);
    if (!mounted) return;
    final now = DateTime.now();
    await saveFile(
      context,
      bytes: bytes,
      name:
          'narudzba_${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.pdf',
      mimeType: 'application/pdf',
      label: 'PDF',
      extension: 'pdf',
    );
  }

  /// Telefon: kartica sa artiklima, količina desno.
  Widget _cards() {
    final error = Theme.of(context).colorScheme.error;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, l) in widget.lines.indexed) ...[
            if (i > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
              child: Row(
                children: [
                  Checkbox(
                    value: _selected.contains(l.itemId),
                    onChanged: (v) => setState(
                      () => v == true
                          ? _selected.add(l.itemId)
                          : _selected.remove(l.itemId),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            'zaliha ${l.stock}',
                            if (l.minQty != null) 'minimum ${l.minQty}',
                            if (l.byAverage) 'prema prosjeku',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 13,
                            fontFeatures: tabularFigures,
                            color: l.stock <= 0 ? error : SankoColors.muted,
                            fontWeight: l.stock <= 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: _qty[l.itemId],
                      textAlign: TextAlign.right,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Naručiti',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final withMin = widget.items.where((i) => i.minQty != null).length;
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    const head = TextStyle(
      color: SankoColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    final order = _order;
    return ListView(
      padding: pagePadding(context),
      children: [
        if (withMin == 0)
          const _Info(
            'Nijedan artikal nema minimum. Postavite ga u Artiklima (npr. KOLA: '
            'minimum 24, naručiti do 72), pa će artikal doći ovdje čim zaliha padne '
            'na minimum. Do tada lista predlaže artikle kojima prema prosjeku zaliha '
            'ističe za manje od dva dana.',
          ),
        if (widget.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(text: 'Ništa ne treba naručiti'),
          )
        else ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Pošalji na Viber'),
                onPressed: order.isEmpty ? null : _viber,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('Kopiraj tekst'),
                onPressed: order.isEmpty ? null : _copy,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Sačuvaj PDF'),
                onPressed: order.isEmpty ? null : _pdf,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isCompact(context))
            _cards()
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          SizedBox(width: 48),
                          Expanded(child: Text('Artikal', style: head)),
                          SizedBox(
                            width: 90,
                            child: Text(
                              'Zaliha',
                              style: head,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(
                              'Minimum',
                              style: head,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(width: 24),
                          SizedBox(
                            width: 110,
                            child: Text(
                              'Naručiti',
                              style: head,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      for (final l in widget.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                child: Checkbox(
                                  value: _selected.contains(l.itemId),
                                  onChanged: (v) => setState(
                                    () => v == true
                                        ? _selected.add(l.itemId)
                                        : _selected.remove(l.itemId),
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
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (l.byAverage)
                                      const Text(
                                        'prema prosjeku, za 7 dana',
                                        style: muted,
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  '${l.stock}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFeatures: tabularFigures,
                                    fontWeight: FontWeight.w700,
                                    color: l.stock <= 0
                                        ? Theme.of(context).colorScheme.error
                                        : SankoColors.ink,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 90,
                                child: Text(
                                  l.minQty == null ? '–' : '${l.minQty}',
                                  textAlign: TextAlign.right,
                                  style: muted.copyWith(
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              SizedBox(
                                width: 110,
                                child: TextField(
                                  controller: _qty[l.itemId],
                                  textAlign: TextAlign.right,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SankoColors.waiting.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: SankoColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: SankoColors.ink, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Narudžba kao jednostavan PDF za dobavljača.
Future<Uint8List> buildOrderPdf({
  required String title,
  required List<(String name, int qty)> lines,
}) async {
  Future<pw.Font> font(String file) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  final doc = pw.Document(
    title: title,
    author: 'Šanko',
    theme: pw.ThemeData.withFont(
      base: await font('Manrope-400.ttf'),
      bold: await font('Manrope-700.ttf'),
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: ['Artikal', 'Količina'],
          data: [
            for (final (name, qty) in lines) [name, '$qty'],
          ],
          cellAlignments: {1: pw.Alignment.centerRight},
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 12),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1),
          },
        ),
      ],
    ),
  );
  return doc.save();
}
