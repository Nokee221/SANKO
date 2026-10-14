import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
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
    final file = XFile.fromData(bytes, mimeType: 'application/pdf', name: name);
    if (kIsWeb) {
      await file.saveTo(name);
      return;
    }
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    if (location == null) return;
    await file.saveTo(location.path);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('PDF je sačuvan: ${location.path}')));
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
                      '${weekdayName(_day)}, ${fmtDate(_day)}',
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
                    ? forecastStock(await repo.currentStock(), history)
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
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
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
                      if (selected != null && selected.isClosed)
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: SankoColors.waiting.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule,
                            size: 18,
                            color: SankoColors.ink,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Smjena ${open.seq} (${open.workerName}) još nije zaključena, '
                              'pa utrošeno i iznos za nju nisu konačni.',
                              style: const TextStyle(
                                color: SankoColors.ink,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => _CloseShiftDialog(
                                shift: open,
                                lines: data.byShift[open.id]!.lines,
                              ),
                            ),
                            child: const Text('Zaključi smjenu'),
                          ),
                        ],
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
                          _Stat(label: 'Rashod', amount: obracun.expenses),
                          _Stat(
                            label: 'Ukupno',
                            amount: obracun.total,
                            highlight: true,
                          ),
                        ],
                      );
                      final expenses = _Expenses(
                        shifts: shown,
                        expenses: data.expenses,
                        showShift: selected == null && data.shifts.length > 1,
                      );
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
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          stats,
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
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _fields.values) {
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
    setState(() => _busy = true);
    final data = AdminScope.of(context);
    final closed = await guard(
      context,
      () => data.adminCloseShift(widget.shift.id, counts),
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
      content: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unesite stanje na kraju smjene za svaki artikal. Nakon zaključenja '
              'konobar je više ne može mijenjati, a sljedeća smjena može početi.',
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _fillEmpty,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Popuni prazna polja kao da nije bilo prodaje'),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.separated(
                itemCount: widget.lines.length,
                separatorBuilder: (_, _) => const Divider(),
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
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
                        '${c.isClosing ? 'ostatak' : 'primljeno'} '
                        '${c.oldValue} → ${c.newValue}',
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
    Widget field(TextEditingController c, String key, {bool enabled = true}) =>
        SizedBox(
          width: 100,
          child: TextField(
            key: ValueKey(key),
            controller: c,
            enabled: enabled,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
            ],
            decoration: const InputDecoration(isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        );

    return AlertDialog(
      title: Text(
        'Ispravka smjene ${widget.shift.seq} (${widget.shift.workerName})',
      ),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Promijenite ostatak ili primljeno gdje je greška. Ispravljen ostatak '
              'postaje početno stanje u sljedećoj smjeni, a svaka promjena se zapisuje.',
            ),
            const SizedBox(height: 14),
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
            Expanded(
              child: ListView.separated(
                itemCount: widget.lines.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, i) {
                  final l = widget.lines[i];
                  final consumed = _consumed(l);
                  final changed = consumed != l.consumed;
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
                        SizedBox(
                          width: 90,
                          child: Text(
                            consumed == null ? '–' : '$consumed',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFeatures: tabularFigures,
                              fontWeight: changed
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                              color: changed
                                  ? SankoColors.navy
                                  : SankoColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Razlog ispravke (npr. greška u brojanju)',
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
