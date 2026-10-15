import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../../domain/stats.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'obracun_pdf.dart';
import 'prosjek_page.dart';
import 'save_file.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

class _DayData {
  const _DayData(
    this.shifts,
    this.byShift,
    this.day,
    this.expenses,
    this.history,
    this.corrections,
    this.stock,
  );

  final List<Shift> shifts;
  final Map<String, Obracun> byShift;
  final Obracun day;
  final Map<String, List<Expense>> expenses;

  /// Prosjeci zadnjih 30 dana prije ovog dana, za poređenje.
  final ItemStats history;

  /// Ispravke smjena ovog dana, najstarije prve.
  final List<ShiftCorrection> corrections;

  /// Procjena zalihe; prazno kad se ne gleda današnji dan.
  final List<StockForecast> stock;
}

/// Obračun po danu, sa izborom cijelog dana ili jedne smjene.
class ObracunPage extends StatefulWidget {
  const ObracunPage({super.key, this.initialDay, this.venueName = ''});

  /// Naziv lokala u zaglavlju PDF-a.
  final String venueName;

  final DateTime? initialDay;

  @override
  State<ObracunPage> createState() => _ObracunPageState();
}

class _ObracunPageState extends State<ObracunPage> {
  late DateTime _day = dateOnly(widget.initialDay ?? DateTime.now());

  /// null znači cijeli dan.
  String? _shiftId;

  void _setDay(DateTime day) => setState(() {
    _day = dateOnly(day);
    _shiftId = null;
  });

  Future<void> _exportPdf(_DayData data, Shift? selected) async {
    final shown = selected == null ? data.shifts : [selected];
    final ids = {for (final s in shown) s.id};
    final title = selected == null
        ? 'Obračun za ${weekdayName(_day)}, ${fmtDate(_day)}'
        : 'Obračun smjene ${selected.seq}, ${fmtDate(_day)}';
    final subtitle = selected == null
        ? '${data.shifts.length} '
              '${plural(data.shifts.length, 'smjena', 'smjene', 'smjena')}: '
              '${data.shifts.map((s) => s.workerName).join(', ')}'
        : '${selected.workerName}, ${fmtTime(selected.openedAt)}–'
              '${selected.isClosed ? fmtTime(selected.closedAt!) : 'u toku'}';
    final bytes = await buildObracunPdf(
      venueName: widget.venueName,
      title: title,
      subtitle: subtitle,
      obracun: selected == null ? data.day : data.byShift[selected.id]!,
      expenses: [
        for (final s in shown)
          for (final e in data.expenses[s.id]!) (s.workerName, e),
      ],
      corrections: data.corrections
          .where((c) => ids.contains(c.shiftId))
          .toList(),
    );
    final name =
        'obracun_${_day.year}-${_day.month.toString().padLeft(2, '0')}-'
        '${_day.day.toString().padLeft(2, '0')}'
        '${selected == null ? '' : '_smjena_${selected.seq}'}.pdf';
    if (!mounted) return;
    await saveFile(
      context,
      bytes: bytes,
      name: name,
      mimeType: 'application/pdf',
      label: 'PDF',
      extension: 'pdf',
    );
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) _setDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Obračun',
          children: [
            // Izbor dana: prethodni, kalendar, sljedeći.
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: SankoColors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Prethodni dan',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () =>
                        _setDay(_day.subtract(const Duration(days: 1))),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 17),
                    label: Text(
                      isCompact(context)
                          ? '${weekdayName(_day).substring(0, 3)}, ${fmtDate(_day)}'
                          : '${weekdayName(_day)}, ${fmtDate(_day)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: SankoColors.ink,
                    ),
                    onPressed: _pickDay,
                  ),
                  IconButton(
                    tooltip: 'Sljedeći dan',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _setDay(_day.add(const Duration(days: 1))),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _setDay(DateTime.now()),
              child: const Text('Danas'),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Osvježi',
              icon: const Icon(Icons.refresh),
              onPressed: () => AdminScope.of(context).refresh(),
            ),
          ],
        ),
        Expanded(
          child: AdminLoader<_DayData>(
            load: (repo) async {
              final shifts = await repo.shiftsOn(_day);
              // Sve smjene dana se učitavaju istovremeno.
              final obracuni = await Future.wait([
                for (final s in shifts) repo.obracunForShift(s.id),
              ]);
              final rashodi = await Future.wait([
                for (final s in shifts) repo.expenses(s.id),
              ]);
              final history = ItemStats.compute(
                await repo.statLines(
                  _day.subtract(const Duration(days: 30)),
                  _day.subtract(const Duration(days: 1)),
                ),
              );
              return _DayData(
                shifts,
                {for (final (i, s) in shifts.indexed) s.id: obracuni[i]},
                Obracun.forDay(obracuni),
                {for (final (i, s) in shifts.indexed) s.id: rashodi[i]},
                history,
                await repo.corrections([for (final s in shifts) s.id]),
                // Zaliha je stanje sada, pa ima smisla samo uz današnji dan.
                _day == dateOnly(DateTime.now())
                    ? forecastStock(
                        await repo.currentStock(),
                        history,
                        minimums: {
                          for (final i in await repo.items())
                            if (i.minQty != null) i.id: i.minQty!,
                        },
                      )
                    : const [],
              );
            },
            builder: (context, data) {
              if (data.shifts.isEmpty) {
                return const EmptyState(text: 'Za ovaj dan nema smjena');
              }
              final selected = data.shifts
                  .where((s) => s.id == _shiftId)
                  .firstOrNull;
              final obracun = selected == null
                  ? data.day
                  : data.byShift[selected.id]!;
              final shown = selected == null ? data.shifts : [selected];
              final open = shown.where((s) => !s.isClosed).firstOrNull;
              return ListView(
                padding: pagePadding(context),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ShiftChip(
                        label: 'Cijeli dan',
                        selected: selected == null,
                        onTap: () => setState(() => _shiftId = null),
                      ),
                      for (final s in data.shifts)
                        _ShiftChip(
                          label:
                              'Smjena ${s.seq}, ${s.workerName}, ${fmtTime(s.openedAt)}–'
                              '${s.isClosed ? fmtTime(s.closedAt!) : 'u toku'}'
                              '${s.closedByAdmin ? ' (zaključio gazda)' : ''}'
                              '${data.corrections.any((c) => c.shiftId == s.id) ? ' (ispravljeno)' : ''}',
                          selected: selected?.id == s.id,
                          onTap: () => setState(() => _shiftId = s.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (selected != null && selected.isClosed) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Ispravi smjenu'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => _CorrectShiftDialog(
                              shift: selected,
                              lines: data.byShift[selected.id]!.lines,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Kuhinja i predaja'),
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => _HandoverDialog(
                              shift: selected,
                              obracun: data.byShift[selected.id]!,
                            ),
                          ),
                        ),
                      ],
                      OutlinedButton.icon(
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 18,
                        ),
                        label: const Text('Izvoz u PDF'),
                        onPressed: () => _exportPdf(data, selected),
                      ),
                    ],
                  ),
                  if (data.stock.any((f) => f.isLow)) ...[
                    const SizedBox(height: 14),
                    _LowStockNote(
                      forecasts: data.stock.where((f) => f.isLow).toList(),
                    ),
                  ],
                  if (open != null) ...[
                    const SizedBox(height: 14),
                    _OpenShiftNote(
                      shift: open,
                      onClose: () => showDialog<void>(
                        context: context,
                        builder: (_) => _CloseShiftDialog(
                          shift: open,
                          lines: data.byShift[open.id]!.lines,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stats = Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          _Stat(label: 'Šank', amount: obracun.sank),
                          _Stat(label: 'Kuhinja', amount: obracun.kitchen),
                          _Stat(label: 'Rashod', amount: obracun.expenses),
                          _Stat(
                            label: 'Za predati',
                            amount: obracun.total,
                            highlight: true,
                          ),
                          if (obracun.handedOver != null)
                            _HandoverStat(obracun: obracun),
                        ],
                      );
                      final expenses = _Expenses(
                        shifts: shown,
                        expenses: data.expenses,
                        showShift: selected == null && data.shifts.length > 1,
                      );
                      if (isCompact(context)) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CompactSummary(obracun: obracun),
                            const SizedBox(height: 12),
                            expenses,
                          ],
                        );
                      }
                      // U uskom prozoru rashod ide ispod iznosa.
                      if (constraints.maxWidth < 1000) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            stats,
                            const SizedBox(height: 14),
                            expenses,
                          ],
                        );
                      }
                      // Iznosi se prelamaju u dva reda, a rashod ide desno.
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 3 * 208 + 2 * 14,
                            ),
                            child: stats,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: expenses),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  ...() {
                    // Poređenje sa prosjekom: po smjeni za jednu smjenu, po danu za cijeli dan.
                    final expected = <String, double>{};
                    for (final l in obracun.lines) {
                      final avg = data.history.item(l.itemId);
                      if (avg == null || l.consumed == null) continue;
                      final enough = selected == null
                          ? data.history.days >= minHistory
                          : avg.shifts >= minHistory;
                      final usual = selected == null
                          ? avg.perDay
                          : avg.perShift;
                      if (enough && isUnusual(l.consumed!, usual)) {
                        expected[l.itemId] = usual;
                      }
                    }
                    return [
                      if (expected.isNotEmpty) ...[
                        _UnusualNote(perShift: selected != null),
                        const SizedBox(height: 12),
                      ],
                      _ObracunTables(
                        lines: obracun.lines,
                        expected: expected,
                        perShift: selected != null,
                      ),
                    ];
                  }(),
                  ...() {
                    final shownIds = {for (final s in shown) s.id};
                    final list = data.corrections
                        .where((c) => shownIds.contains(c.shiftId))
                        .toList();
                    if (list.isEmpty) return const <Widget>[];
                    return [
                      const SizedBox(height: 20),
                      _Corrections(
                        corrections: list,
                        shifts: data.shifts,
                        showShift: selected == null,
                      ),
                    ];
                  }(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Gazda zaključuje smjenu umjesto konobara: unosi stanje koje nedostaje i potvrđuje.
class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog({required this.shift, required this.lines});

  final Shift shift;
  final List<ObracunLine> lines;

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  late final _fields = {
    for (final l in widget.lines)
      l.itemId: TextEditingController(text: l.closing?.toString() ?? ''),
  };
  final _kitchen = TextEditingController();
  final _cash = TextEditingController();
  final _card = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._fields.values, _kitchen, _cash, _card]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Prazna polja dobijaju stanje kao da ništa nije prodano.
  void _fillEmpty() {
    for (final l in widget.lines) {
      final field = _fields[l.itemId]!;
      if (field.text.trim().isEmpty) field.text = '${l.total}';
    }
    setState(() {});
  }

  Future<void> _close() async {
    final counts = <String, int>{};
    for (final l in widget.lines) {
      final value = int.tryParse(_fields[l.itemId]!.text.trim());
      if (value == null) {
        showError(context, 'Unesite stanje za ${l.name}.');
        return;
      }
      counts[l.itemId] = value;
    }
    // Predaja nije obavezna: konobar je možda otišao bez predaje novca.
    final kitchen = _money(_kitchen);
    final cash = _cash.text.trim().isEmpty ? null : _money(_cash);
    final card = _money(_card);
    if (kitchen == null ||
        card == null ||
        (_cash.text.trim().isNotEmpty && cash == null)) {
      showError(context, 'Iznos nije ispravan. Primjer: 120,50');
      return;
    }
    // Bez gotovine nema predaje, pa bi kuhinja i kartice nestale.
    if (cash == null && (kitchen > 0 || card > 0)) {
      showError(
        context,
        'Unesite i gotovinu (0 ako nije predana), ili ostavite predaju praznu.',
      );
      return;
    }
    setState(() => _busy = true);
    final data = AdminScope.of(context);
    final closed = await guard(
      context,
      () => data.adminCloseShift(
        widget.shift.id,
        counts,
        handover: cash == null
            ? null
            : Handover(kitchen: kitchen, cash: cash, card: card),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (closed) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    return AlertDialog(
      title: Text(
        'Zaključiti smjenu ${widget.shift.seq} (${widget.shift.workerName})?',
      ),
      content: _DialogBody(
        width: 520,
        height: 480,
        header: [
          const Text(
            'Unesite stanje na kraju smjene za svaki artikal. Nakon zaključenja '
            'konobar je više ne može mijenjati, a sljedeća smjena može početi.',
          ),
          const SizedBox(height: 12),
          _MoneyRow(
            fields: [
              _MoneyField(controller: _kitchen, label: 'Kuhinja'),
              _MoneyField(controller: _cash, label: 'Gotovina'),
              _MoneyField(controller: _card, label: 'Kartice'),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Predaja nije obavezna; može se upisati i kasnije.',
            style: TextStyle(color: SankoColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _fillEmpty,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('Popuni prazna polja kao da nije bilo prodaje'),
          ),
          const SizedBox(height: 4),
        ],
        itemCount: widget.lines.length,
        itemBuilder: (context, i) {
          final l = widget.lines[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        l.kind == ItemKind.counter
                            ? 'Prethodno stanje brojača ${l.opening}'
                            : 'Bilo ukupno ${l.total}',
                        style: muted,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _fields[l.itemId],
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'stanje',
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _busy ? null : _close,
          child: const Text('Zaključi smjenu'),
        ),
      ],
    );
  }
}

/// Zapisi o ispravkama: šta je, kada i zašto promijenjeno.
class _Corrections extends StatelessWidget {
  const _Corrections({
    required this.corrections,
    required this.shifts,
    required this.showShift,
  });

  final List<ShiftCorrection> corrections;
  final List<Shift> shifts;
  final bool showShift;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ispravke',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final c in corrections)
              if (isCompact(context))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.itemName}: ${correctionText(c)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      Text(
                        [
                          '${fmtDate(c.correctedAt)} ${fmtTime(c.correctedAt)}',
                          if (showShift)
                            'smjena ${shifts.firstWhere((s) => s.id == c.shiftId).seq}',
                          ?c.note,
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          '${fmtDate(c.correctedAt)} ${fmtTime(c.correctedAt)}',
                          style: muted,
                        ),
                      ),
                      if (showShift)
                        SizedBox(
                          width: 90,
                          child: Text(
                            'Smjena ${shifts.firstWhere((s) => s.id == c.shiftId).seq}',
                            style: muted,
                          ),
                        ),
                      SizedBox(
                        width: 180,
                        child: Text(
                          c.itemName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: Text(
                          correctionText(c),
                          style: const TextStyle(fontFeatures: tabularFigures),
                        ),
                      ),
                      Expanded(child: Text(c.note ?? '', style: muted)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Gazda ispravlja ostatak i primljeno u zaključenoj smjeni.
class _CorrectShiftDialog extends StatefulWidget {
  const _CorrectShiftDialog({required this.shift, required this.lines});

  final Shift shift;
  final List<ObracunLine> lines;

  @override
  State<_CorrectShiftDialog> createState() => _CorrectShiftDialogState();
}

class _CorrectShiftDialogState extends State<_CorrectShiftDialog> {
  late final _closing = {
    for (final l in widget.lines)
      l.itemId: TextEditingController(text: '${l.closing ?? ''}'),
  };
  late final _received = {
    for (final l in widget.lines)
      l.itemId: TextEditingController(text: '${l.received}'),
  };
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._closing.values, ..._received.values, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Utrošeno sa trenutno unesenim brojevima; null dok polje nije ispravno.
  int? _consumed(ObracunLine l) {
    final closing = int.tryParse(_closing[l.itemId]!.text.trim());
    final received = int.tryParse(_received[l.itemId]!.text.trim());
    if (closing == null || received == null) return null;
    return l.kind == ItemKind.counter
        ? closing - l.opening
        : l.opening + received - closing;
  }

  Future<void> _save() async {
    final changes = <ItemCorrection>[];
    for (final l in widget.lines) {
      final closing = int.tryParse(_closing[l.itemId]!.text.trim());
      final received = int.tryParse(_received[l.itemId]!.text.trim());
      if (closing == null || received == null) {
        showError(context, 'Provjerite brojeve za ${l.name}.');
        return;
      }
      if (closing != l.closing || received != l.received) {
        changes.add(
          ItemCorrection(
            itemId: l.itemId,
            closing: closing != l.closing ? closing : null,
            received: received != l.received ? received : null,
          ),
        );
      }
    }
    if (changes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = true);
    final data = AdminScope.of(context);
    final saved = await guard(
      context,
      () => data.correctShift(widget.shift.id, changes, note: _note.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(
      color: SankoColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    final compact = isCompact(context);
    Widget field(
      TextEditingController c,
      String key, {
      double? width = 100,
      String? label,
    }) => SizedBox(
      width: width,
      child: TextField(
        key: ValueKey(key),
        controller: c,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        decoration: InputDecoration(isDense: true, labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );
    Widget consumedText(ObracunLine l, int? consumed) {
      final changed = consumed != l.consumed;
      return Text(
        consumed == null ? '–' : '$consumed',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontFeatures: tabularFigures,
          fontWeight: changed ? FontWeight.w800 : FontWeight.w400,
          color: changed ? SankoColors.navy : SankoColors.muted,
        ),
      );
    }

    return AlertDialog(
      title: Text(
        'Ispravka smjene ${widget.shift.seq} (${widget.shift.workerName})',
      ),
      content: _DialogBody(
        width: 640,
        height: 520,
        header: [
          const Text(
            'Promijenite ostatak ili primljeno gdje je greška. Ispravljen ostatak '
            'postaje početno stanje u sljedećoj smjeni, a svaka promjena se zapisuje.',
          ),
          const SizedBox(height: 14),
          if (!compact)
            const Row(
              children: [
                Expanded(child: Text('Artikal', style: header)),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Primljeno',
                    style: header,
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text(
                    'Ostatak',
                    style: header,
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    'Utrošeno',
                    style: header,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
        ],
        itemCount: widget.lines.length,
        itemBuilder: (context, i) {
          final l = widget.lines[i];
          final consumed = _consumed(l);
          // Telefon: naziv, pa polja ispod njega.
          if (compact) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (l.kind != ItemKind.counter) ...[
                        Expanded(
                          child: field(
                            _received[l.itemId]!,
                            'primljeno-${l.itemId}',
                            width: null,
                            label: 'Primljeno',
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: field(
                          _closing[l.itemId]!,
                          'ostatak-${l.itemId}',
                          width: null,
                          label: l.kind == ItemKind.counter
                              ? 'Brojač'
                              : 'Ostatak',
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'utrošeno',
                              style: TextStyle(
                                color: SankoColors.muted,
                                fontSize: 11,
                              ),
                            ),
                            consumedText(l, consumed),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                // Brojač nema ulaz.
                if (l.kind == ItemKind.counter)
                  const SizedBox(
                    width: 100,
                    child: Text(
                      '–',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: SankoColors.muted),
                    ),
                  )
                else
                  field(_received[l.itemId]!, 'primljeno-${l.itemId}'),
                const SizedBox(width: 12),
                field(_closing[l.itemId]!, 'ostatak-${l.itemId}'),
                SizedBox(width: 90, child: consumedText(l, consumed)),
              ],
            ),
          );
        },
        footer: [
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Razlog ispravke (npr. greška u brojanju)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Sačuvaj ispravku'),
        ),
      ],
    );
  }
}

class _ShiftChip extends StatelessWidget {
  const _ShiftChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SankoColors.navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? SankoColors.navy : SankoColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures,
              color: selected ? Colors.white : SankoColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Jedan od tri glavna iznosa obračuna.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amount,
    this.highlight = false,
  });

  final String label;
  final int amount;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      height: 116,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: highlight ? SankoColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? SankoColors.navy : SankoColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: highlight ? SankoColors.brass : SankoColors.muted,
            ),
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  fmtMoney(amount),
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    fontFeatures: tabularFigures,
                    color: highlight ? Colors.white : SankoColors.ink,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'KM',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: highlight ? Colors.white70 : SankoColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tabela kao u knjizi šanka; na širokom ekranu se dijeli u dvije kolone.
/// Predano gotovinom i karticama, i razlika prema za predati.
class _HandoverStat extends StatelessWidget {
  const _HandoverStat({required this.obracun});

  final Obracun obracun;

  @override
  Widget build(BuildContext context) {
    final difference = obracun.difference!;
    final error = Theme.of(context).colorScheme.error;
    final (label, color) = difference < 0
        ? ('Manjak', error)
        : difference > 0
        ? ('Višak', SankoColors.ink)
        : ('Tačno predano', SankoColors.muted);
    return Container(
      width: 250,
      height: 116,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: difference < 0 ? error.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: difference < 0 ? error : SankoColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Predano',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SankoColors.muted,
            ),
          ),
          Text(
            fmtKm(obracun.handedOver!),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures,
            ),
          ),
          Text(
            'gotovina ${fmtMoney(obracun.cash!)}, kartice ${fmtMoney(obracun.card ?? 0)}',
            style: const TextStyle(fontSize: 12, color: SankoColors.muted),
          ),
          const Spacer(),
          Text(
            difference == 0 ? label : '$label ${fmtKm(difference.abs())}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sadržaj dijaloga sa listom artikala. Na računaru je zaglavlje iznad liste koja ima
/// svoj klizač; na telefonu se zaglavlje, lista i podnožje pomjeraju zajedno, u visini
/// koja ostane iznad tastature.
class _DialogBody extends StatelessWidget {
  const _DialogBody({
    required this.width,
    required this.height,
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    this.footer = const [],
  });

  final double width;
  final double height;
  final List<Widget> header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    if (!isCompact(context)) {
      return SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            Expanded(
              child: ListView.separated(
                itemCount: itemCount,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: itemBuilder,
              ),
            ),
            ...footer,
          ],
        ),
      );
    }
    // Naslov, dugmad i rubovi dijaloga zauzimaju oko 260 tačaka.
    final media = MediaQuery.of(context);
    final free = media.size.height - media.viewInsets.bottom - 260;
    return SizedBox(
      width: width,
      height: free.clamp(160.0, height * 1.4),
      child: ListView(
        children: [
          ...header,
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) const Divider(),
            itemBuilder(context, i),
          ],
          ...footer,
        ],
      ),
    );
  }
}

/// Polje za iznos u KM; prazno znači nula.
class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    // Na telefonu tri polja stanu u red bez oznake valute.
    final compact = isCompact(context);
    return SizedBox(
      width: compact ? null : 150,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          suffixText: compact ? null : 'KM',
        ),
        onChanged: (_) => onChanged?.call(),
      ),
    );
  }
}

/// Polja za kuhinju i predaju: na telefonu u jednom redu, na računaru jedno do drugog.
class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.fields});

  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    if (!isCompact(context)) {
      return Wrap(spacing: 12, runSpacing: 12, children: fields);
    }
    return Row(
      children: [
        for (final (i, f) in fields.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: f),
        ],
      ],
    );
  }
}

/// Iznos iz polja u feninzima; prazno je nula, null kad nije ispravan.
int? _money(TextEditingController c) =>
    c.text.trim().isEmpty ? 0 : parseMoney(c.text.replaceAll(' ', ''));

/// Gazda upisuje ili ispravlja kuhinju i predaju zaključene smjene.
class _HandoverDialog extends StatefulWidget {
  const _HandoverDialog({required this.shift, required this.obracun});

  final Shift shift;
  final Obracun obracun;

  @override
  State<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends State<_HandoverDialog> {
  late final _kitchen = TextEditingController(
    text: fmtMoney(widget.obracun.kitchen).replaceAll('.', ''),
  );
  late final _cash = TextEditingController(
    text: widget.obracun.cash == null
        ? ''
        : fmtMoney(widget.obracun.cash!).replaceAll('.', ''),
  );
  late final _card = TextEditingController(
    text: widget.obracun.card == null
        ? ''
        : fmtMoney(widget.obracun.card!).replaceAll('.', ''),
  );
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_kitchen, _cash, _card, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final kitchen = _money(_kitchen);
    final cash = _money(_cash);
    final card = _money(_card);
    if (kitchen == null || cash == null || card == null) {
      showError(context, 'Iznos nije ispravan. Primjer: 120,50');
      return;
    }
    setState(() => _busy = true);
    final data = AdminScope.of(context);
    final saved = await guard(
      context,
      () => data.setHandover(
        widget.shift.id,
        Handover(kitchen: kitchen, cash: cash, card: card),
        note: _note.text,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final kitchen = _money(_kitchen);
    final cash = _money(_cash);
    final card = _money(_card);
    final preview = kitchen == null || cash == null || card == null
        ? null
        : widget.obracun.withHandover(kitchen: kitchen, cash: cash, card: card);
    return AlertDialog(
      scrollable: true,
      title: Text(
        'Kuhinja i predaja, smjena ${widget.shift.seq} (${widget.shift.workerName})',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upišite iznos kuhinje i koliko je novca predano. Svaka promjena se zapisuje.',
            ),
            const SizedBox(height: 16),
            _MoneyRow(
              fields: [
                _MoneyField(
                  controller: _kitchen,
                  label: 'Kuhinja',
                  onChanged: () => setState(() {}),
                ),
                _MoneyField(
                  controller: _cash,
                  label: 'Gotovina',
                  onChanged: () => setState(() {}),
                ),
                _MoneyField(
                  controller: _card,
                  label: 'Kartice',
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (preview != null)
              Text(
                'Za predati ${fmtKm(preview.total)}, predano ${fmtKm(preview.handedOver!)}: '
                '${preview.difference! < 0
                    ? 'manjak ${fmtKm(-preview.difference!)}'
                    : preview.difference! > 0
                    ? 'višak ${fmtKm(preview.difference!)}'
                    : 'tačno'}.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Razlog (npr. konobar donio ostatak novca)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}

/// Upozorenje na nisku zalihu na današnjem obračunu.
class _LowStockNote extends StatelessWidget {
  const _LowStockNote({required this.forecasts});

  final List<StockForecast> forecasts;

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
          const Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: SankoColors.ink,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Niska zaliha: '
              '${forecasts.map((f) => '${f.level.name} (${stockText(f)})').join(', ')}.',
              style: const TextStyle(color: SankoColors.ink, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnusualNote extends StatelessWidget {
  const _UnusualNote({required this.perShift});

  final bool perShift;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SankoColors.waiting.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_outlined, size: 18, color: SankoColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Označeni artikli imaju mnogo veću potrošnju nego inače '
              '(prosjek ${perShift ? 'po smjeni' : 'po danu'} zadnjih 30 dana). '
              'Provjerite brojanje i ulaz.',
              style: const TextStyle(color: SankoColors.ink, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ObracunTables extends StatelessWidget {
  const _ObracunTables({
    required this.lines,
    required this.expected,
    required this.perShift,
  });

  final List<ObracunLine> lines;

  /// Uobičajena potrošnja za artikle čija je potrošnja neobično velika.
  final Map<String, double> expected;
  final bool perShift;

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) {
      return _ObracunCards(
        lines: lines,
        expected: expected,
        perShift: perShift,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // U uskom prozoru tabela zadržava čitljivu širinu i pomjera se vodoravno.
        if (constraints.maxWidth < 780) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 780,
              child: _ObracunTable(
                lines: lines,
                firstNumber: 1,
                expected: expected,
                perShift: perShift,
              ),
            ),
          );
        }
        // Ispod ove širine brojevi u dvije kolone ne stanu, pa ostaje jedna tabela.
        if (constraints.maxWidth < 1450) {
          return Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: _ObracunTable(
                lines: lines,
                firstNumber: 1,
                expected: expected,
                perShift: perShift,
              ),
            ),
          );
        }
        final half = (lines.length + 1) ~/ 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ObracunTable(
                lines: lines.sublist(0, half),
                firstNumber: 1,
                expected: expected,
                perShift: perShift,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _ObracunTable(
                lines: lines.sublist(half),
                firstNumber: half + 1,
                expected: expected,
                perShift: perShift,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ObracunTable extends StatelessWidget {
  const _ObracunTable({
    required this.lines,
    required this.firstNumber,
    required this.expected,
    required this.perShift,
  });

  final List<ObracunLine> lines;
  final int firstNumber;
  final Map<String, double> expected;
  final bool perShift;

  @override
  Widget build(BuildContext context) {
    const header = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      color: SankoColors.muted,
    );
    const number = TextStyle(
      fontSize: 14,
      fontFeatures: tabularFigures,
      color: SankoColors.ink,
    );

    Widget cell(String s, {TextStyle style = number, bool right = true}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            s,
            style: style,
            textAlign: right ? TextAlign.right : TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    String qty(int? v) => v == null ? '–' : '$v';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: SankoColors.line),
        ),
        columnWidths: const {
          0: FixedColumnWidth(48),
          1: FlexColumnWidth(2.2),
          2: FlexColumnWidth(),
          3: FlexColumnWidth(),
          4: FlexColumnWidth(),
          5: FlexColumnWidth(),
          6: FlexColumnWidth(),
          7: FlexColumnWidth(0.9),
          8: FlexColumnWidth(1.2),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: SankoColors.paper),
            children: [
              cell('#', style: header),
              cell('Naziv artikla', style: header, right: false),
              cell('Ostatak prije', style: header),
              cell('Primljeno', style: header),
              cell('Ukupno', style: header),
              cell('Utrošeno', style: header),
              cell('Ostatak', style: header),
              cell('Cijena', style: header),
              cell('Iznos', style: header),
            ],
          ),
          for (final (i, l) in lines.indexed)
            TableRow(
              decoration: l.hasAnomaly
                  ? const BoxDecoration(color: Color(0xFFFDECEC))
                  : expected.containsKey(l.itemId)
                  ? BoxDecoration(
                      color: SankoColors.waiting.withValues(alpha: 0.18),
                    )
                  : null,
              children: [
                cell(
                  '${firstNumber + i}',
                  style: number.copyWith(color: SankoColors.muted),
                ),
                cell(
                  l.name,
                  right: false,
                  style: number.copyWith(fontWeight: FontWeight.w700),
                ),
                cell('${l.opening}'),
                cell(l.received == 0 ? '' : '${l.received}'),
                cell('${l.total}'),
                if (expected.containsKey(l.itemId))
                  Tooltip(
                    message:
                        'Inače oko ${fmtAvg(expected[l.itemId]!)} '
                        '${perShift ? 'po smjeni' : 'po danu'}',
                    child: cell(
                      qty(l.consumed),
                      style: number.copyWith(fontWeight: FontWeight.w800),
                    ),
                  )
                else
                  cell(qty(l.consumed)),
                cell(qty(l.closing)),
                cell(
                  fmtMoney(l.price),
                  style: number.copyWith(color: SankoColors.muted),
                ),
                cell(
                  l.amount == null || l.amount == 0 ? '–' : fmtMoney(l.amount!),
                  style: number.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Expenses extends StatelessWidget {
  const _Expenses({
    required this.shifts,
    required this.expenses,
    required this.showShift,
  });

  final List<Shift> shifts;
  final Map<String, List<Expense>> expenses;
  final bool showShift;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final s in shifts)
        for (final e in expenses[s.id]!) (s, e),
    ];
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 116),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Rashod po stavkama',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: SankoColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const Text('Nema rashoda', style: TextStyle(fontSize: 15)),
              for (final (s, e) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(fmtTime(e.createdAt), style: muted),
                      ),
                      Expanded(
                        child: Text(
                          e.description,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (showShift)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(s.workerName, style: muted),
                        ),
                      Text(
                        fmtMoney(e.amount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Smjena koja još nije zaključena, sa dugmetom da je gazda zaključi.
class _OpenShiftNote extends StatelessWidget {
  const _OpenShiftNote({required this.shift, required this.onClose});

  final Shift shift;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.schedule, size: 18, color: SankoColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Smjena ${shift.seq} (${shift.workerName}) još nije zaključena, '
            'pa utrošeno i iznos za nju nisu konačni.',
            style: const TextStyle(color: SankoColors.ink, fontSize: 14),
          ),
        ),
      ],
    );
    final button = FilledButton(
      onPressed: onClose,
      child: const Text('Zaključi smjenu'),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SankoColors.waiting.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [text, const SizedBox(height: 12), button],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 12),
                button,
              ],
            ),
    );
  }
}

/// Iznosi obračuna na telefonu: jedna kartica umjesto pet velikih.
class _CompactSummary extends StatelessWidget {
  const _CompactSummary({required this.obracun});

  final Obracun obracun;

  @override
  Widget build(BuildContext context) {
    final difference = obracun.difference;
    final error = Theme.of(context).colorScheme.error;
    Widget row(String label, int amount, {bool minus = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
          Text(
            '${minus && amount > 0 ? '− ' : ''}${fmtKm(amount)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            color: SankoColors.navy,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Za predati',
                style: TextStyle(
                  color: SankoColors.brass,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  fmtKm(obracun.total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              row('Šank', obracun.sank),
              row('Kuhinja', obracun.kitchen),
              row('Rashod', obracun.expenses, minus: true),
            ],
          ),
        ),
        if (difference != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(
              color: difference < 0
                  ? error.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: difference < 0 ? error : SankoColors.line,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Predano ${fmtKm(obracun.handedOver!)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                      Text(
                        'gotovina ${fmtMoney(obracun.cash!)}, '
                        'kartice ${fmtMoney(obracun.card ?? 0)}',
                        style: const TextStyle(
                          color: SankoColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  difference < 0
                      ? 'Manjak ${fmtKm(-difference)}'
                      : difference > 0
                      ? 'Višak ${fmtKm(difference)}'
                      : 'Tačno',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: difference < 0 ? error : SankoColors.ink,
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Artikli obračuna na telefonu: kartica po artiklu umjesto tabele. Prvo se vide
/// samo artikli koji su prodani, primljeni ili traže pažnju.
class _ObracunCards extends StatefulWidget {
  const _ObracunCards({
    required this.lines,
    required this.expected,
    required this.perShift,
  });

  final List<ObracunLine> lines;
  final Map<String, double> expected;
  final bool perShift;

  @override
  State<_ObracunCards> createState() => _ObracunCardsState();
}

class _ObracunCardsState extends State<_ObracunCards> {
  bool _all = false;

  bool _matters(ObracunLine l) =>
      (l.consumed ?? 0) != 0 ||
      l.received != 0 ||
      l.hasAnomaly ||
      widget.expected.containsKey(l.itemId);

  String _detail(ObracunLine l) {
    final sold = l.consumed == null
        ? ''
        : ' · ${l.kind == ItemKind.counter ? '' : 'utrošeno '}'
              '${l.consumed} × ${fmtMoney(l.price)}';
    if (l.kind == ItemKind.counter) {
      final end = l.closing == null ? '' : ' → ${l.closing}';
      return 'brojač ${l.opening}$end$sold';
    }
    final received = l.received == 0 ? '' : ' + ${l.received}';
    final end = l.closing == null ? '' : ' → ${l.closing}';
    return '${l.opening}$received$end$sold';
  }

  @override
  Widget build(BuildContext context) {
    final shown = _all ? widget.lines : widget.lines.where(_matters).toList();
    final hidden = widget.lines.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Artikli',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (_all || hidden > 0)
              TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Samo prodano' : 'Svi artikli (+$hidden)'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (shown.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Još ništa nije prodano.'),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, l) in shown.indexed) ...[
                  if (i > 0) const Divider(),
                  _card(l),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _card(ObracunLine l) {
    final usual = widget.expected[l.itemId];
    return Container(
      color: l.hasAnomaly
          ? const Color(0xFFFDECEC)
          : usual != null
          ? SankoColors.waiting.withValues(alpha: 0.18)
          : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                l.amount == null || l.amount == 0 ? '–' : fmtMoney(l.amount!),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _detail(l),
            style: const TextStyle(
              color: SankoColors.muted,
              fontSize: 13,
              fontFeatures: tabularFigures,
            ),
          ),
          if (l.hasAnomaly)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(
                'Prebrojano više nego što je moglo biti',
                style: TextStyle(
                  color: Color(0xFFB3261E),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (usual != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Neobično mnogo: inače oko ${fmtAvg(usual)} '
                '${widget.perShift ? 'po smjeni' : 'po danu'}',
                style: const TextStyle(
                  color: SankoColors.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
