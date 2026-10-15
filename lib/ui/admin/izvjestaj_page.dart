import 'package:flutter/material.dart';

import '../../domain/report.dart';
import '../../domain/xlsx_writer.dart';
import '../format.dart';
import '../theme.dart';
import 'layout.dart';
import 'save_file.dart';
import 'scope.dart';
import 'widgets.dart';

const _months = [
  'januar',
  'februar',
  'mart',
  'april',
  'maj',
  'juni',
  'juli',
  'august',
  'septembar',
  'oktobar',
  'novembar',
  'decembar',
];

const _weekdayShort = ['Pon', 'Uto', 'Sri', 'Čet', 'Pet', 'Sub', 'Ned'];

String _monthName(DateTime m) => '${_months[m.month - 1]} ${m.year}.';

DateTime _lastDay(DateTime month) => DateTime(month.year, month.month + 1, 0);

/// Mjesečni pregled: promet i poređenje sa prethodnim mjesecom, promet po danu u
/// sedmici, najprodavaniji artikli i izvještaj po konobaru, sa izvozom u Excel.
class IzvjestajPage extends StatefulWidget {
  const IzvjestajPage({super.key, this.venueName = ''});

  final String venueName;

  @override
  State<IzvjestajPage> createState() => _IzvjestajPageState();
}

class _IzvjestajPageState extends State<IzvjestajPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  Future<void> _export(MonthReport r) async {
    final bytes = buildXlsx([
      XlsxSheet(
        name: 'Dani',
        header: const [
          'Datum',
          'Smjena',
          'Konobar',
          'Šank',
          'Kuhinja',
          'Rashod',
          'Za predati',
          'Gotovina',
          'Kartice',
          'Razlika',
        ],
        widths: const [12, 8, 18, 12, 12, 12, 12, 12, 12, 12],
        rows: [
          for (final s in r.shifts)
            [
              fmtDate(s.businessDate),
              s.seq,
              s.workerName,
              XlsxMoney(s.sank),
              XlsxMoney(s.kitchen ?? 0),
              XlsxMoney(s.expenses),
              XlsxMoney(s.total),
              if (s.cash == null) null else XlsxMoney(s.cash!),
              if (s.card == null) null else XlsxMoney(s.card!),
              if (s.difference == null) null else XlsxMoney(s.difference!),
            ],
        ],
      ),
      XlsxSheet(
        name: 'Artikli',
        header: const ['Artikal', 'Prodano', 'Promet'],
        widths: const [24, 10, 14],
        rows: [
          for (final i in r.items) [i.name, i.qty, XlsxMoney(i.amount)],
        ],
      ),
      XlsxSheet(
        name: 'Konobari',
        header: const [
          'Konobar',
          'Smjena',
          'Promet',
          'Smjena s manjkom',
          'Manjak',
          'Višak',
          'Sumnjiva brojanja',
        ],
        widths: const [18, 8, 14, 16, 12, 12, 16],
        rows: [
          for (final w in r.workers)
            [
              w.name,
              w.shifts.length,
              XlsxMoney(w.revenue),
              w.shortShifts.length,
              XlsxMoney(w.shortage),
              XlsxMoney(w.surplus),
              w.anomalies,
            ],
        ],
      ),
    ]);
    if (!mounted) return;
    await saveFile(
      context,
      bytes: bytes,
      name:
          'izvjestaj_${_month.year}-${_month.month.toString().padLeft(2, '0')}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      label: 'Excel',
      extension: 'xlsx',
    );
  }

  @override
  Widget build(BuildContext context) {
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Izvještaj',
          children: [
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
                    tooltip: 'Prethodni mjesec',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shift(-1),
                  ),
                  SizedBox(
                    width: 150,
                    child: Text(
                      _monthName(_month),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sljedeći mjesec',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _month == thisMonth ? null : () => _shift(1),
                  ),
                ],
              ),
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
          child: AdminLoader<MonthReport>(
            load: (data) async {
              final previous = DateTime(_month.year, _month.month - 1);
              // Prethodni i ovaj mjesec u jednom upitu.
              final all = await data.shiftSummaries(previous, _lastDay(_month));
              return MonthReport(
                month: _month,
                shifts: [
                  for (final s in all)
                    if (!s.businessDate.isBefore(_month)) s,
                ],
                // Mjesec u toku se poredi sa istim brojem dana prošlog mjeseca.
                previous: [
                  for (final s in all)
                    if (s.businessDate.isBefore(_month) &&
                        (_month != thisMonth ||
                            s.businessDate.day <= DateTime.now().day))
                      s,
                ],
                lines: await data.statLines(_month, _lastDay(_month)),
              );
            },
            builder: (context, r) {
              if (r.shifts.isEmpty) {
                return const EmptyState(
                  text: 'U ovom mjesecu nema zaključenih smjena',
                );
              }
              return ListView(
                padding: pagePadding(context),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.table_view_outlined, size: 18),
                      label: const Text('Izvoz u Excel'),
                      onPressed: () => _export(r),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Kpis(report: r),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, c) {
                      final weekdays = _Panel(
                        title: 'Prosječan promet po danu u sedmici',
                        child: _Bars(
                          labels: _weekdayShort,
                          values: r.weekdays.map((v) => v.round()).toList(),
                          tooltip: (i, v) =>
                              '${_weekdayShort[i]}: prosječno ${fmtKm(v)}',
                        ),
                      );
                      final days = _lastDay(r.month).day;
                      final daily = r.daily;
                      final perDay = _Panel(
                        title: 'Promet po danu',
                        child: _Bars(
                          labels: [
                            for (var d = 1; d <= days; d++)
                              d == 1 || d % 5 == 0 ? '$d' : '',
                          ],
                          values: [
                            for (var d = 1; d <= days; d++)
                              daily[DateTime(r.month.year, r.month.month, d)] ??
                                  0,
                          ],
                          tooltip: (i, v) =>
                              '${fmtDate(DateTime(r.month.year, r.month.month, i + 1))}: ${fmtKm(v)}',
                        ),
                      );
                      if (c.maxWidth < 1000) {
                        return Column(
                          children: [
                            weekdays,
                            const SizedBox(height: 14),
                            perDay,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: weekdays),
                          const SizedBox(width: 14),
                          Expanded(flex: 3, child: perDay),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _Workers(workers: r.workers),
                  const SizedBox(height: 20),
                  _TopItems(items: r.items, revenue: r.sank),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.report});

  final MonthReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final change = r.change;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Na telefonu glavni iznos ide preko cijele širine, a ostali po dva u redu.
        final compact = isCompact(context);
        final full = compact ? constraints.maxWidth : 230.0;
        final half = compact ? (constraints.maxWidth - 12) / 2 : 230.0;
        return _kpis(r, change, compact ? 12.0 : 14.0, full, half);
      },
    );
  }

  Widget _kpis(
    MonthReport r,
    double? change,
    double spacing,
    double full,
    double half,
  ) {
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        _Kpi(
          width: full,
          label: 'Promet (šank + kuhinja)',
          value: fmtKm(r.revenue),
          note: change == null
              ? 'nema podataka za prošli mjesec'
              : '${change >= 0 ? '+' : '−'}${fmtAvg(change.abs())} % prema '
                    '${r.month == DateTime(DateTime.now().year, DateTime.now().month) ? 'istom periodu prošlog mjeseca' : 'prošlom mjesecu'}',
          highlight: true,
        ),
        _Kpi(
          width: half,
          label: 'Prosjek po danu',
          value: fmtKm(r.perDay.round()),
          note:
              '${r.days} ${plural(r.days, 'radni dan', 'radna dana', 'radnih dana')}',
        ),
        _Kpi(
          width: half,
          label: 'Šank / kuhinja',
          value: fmtKm(r.sank),
          note: 'kuhinja ${fmtKm(r.kitchen)}',
        ),
        _Kpi(
          width: half,
          label: 'Rashod',
          value: fmtKm(r.expenses),
          note:
              '${r.shifts.length} ${plural(r.shifts.length, 'smjena', 'smjene', 'smjena')}',
        ),
        _Kpi(
          width: half,
          label: 'Manjak u predaji',
          value: fmtKm(r.shortage),
          note: [
            r.shortage == 0
                ? 'nijedna smjena'
                : '${r.shortShifts.length} '
                      '${plural(r.shortShifts.length, 'smjena', 'smjene', 'smjena')}',
            if (r.surplus > 0) 'višak ${fmtKm(r.surplus)}',
          ].join(' · '),
          alert: r.shortage > 0,
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.width,
    required this.label,
    required this.value,
    required this.note,
    this.highlight = false,
    this.alert = false,
  });

  final double width;
  final String label;
  final String value;
  final String note;
  final bool highlight;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: highlight
            ? SankoColors.navy
            : alert
            ? error.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? SankoColors.navy
              : alert
              ? error
              : SankoColors.line,
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
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                fontFeatures: tabularFigures,
                color: highlight ? Colors.white : SankoColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(
              fontSize: 12,
              color: highlight ? Colors.white70 : SankoColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Stubičasti grafikon jedne serije: tanki stubići od osnovne linije, zaobljeni
/// samo na vrhu, sa razmakom između njih; vrijednost se vidi na prelazu mišem,
/// a uz najveći stubić je napisana.
class _Bars extends StatelessWidget {
  const _Bars({
    required this.labels,
    required this.values,
    required this.tooltip,
  });

  final List<String> labels;
  final List<int> values;
  final String Function(int index, int value) tooltip;

  static const _height = 160.0;

  @override
  Widget build(BuildContext context) {
    final max = values.fold(0, (a, b) => b > a ? b : a);
    final top = values.indexOf(max);
    return Column(
      children: [
        SizedBox(
          height: _height + 22,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (i, v) in values.indexed)
                Expanded(
                  child: Tooltip(
                    message: tooltip(i, v),
                    waitDuration: Duration.zero,
                    child: Container(
                      // Cijela kolona prima prelaz mišem, ne samo stubić.
                      color: Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Oznaka smije biti šira od uskog stubića.
                          if (i == top && max > 0)
                            SizedBox(
                              height: 14,
                              child: OverflowBox(
                                minWidth: 0,
                                maxWidth: 80,
                                child: Text(
                                  softWrap: false,
                                  fmtMoney(v).split(',').first,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: SankoColors.ink,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Container(
                            height: max == 0 ? 0 : _height * v / max,
                            constraints: const BoxConstraints(maxWidth: 28),
                            decoration: const BoxDecoration(
                              color: SankoColors.navy,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: SankoColors.line),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: SizedBox(
                  height: 14,
                  child: OverflowBox(
                    minWidth: 0,
                    maxWidth: 80,
                    child: Text(
                      l,
                      textAlign: TextAlign.center,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 11,
                        color: SankoColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Izvještaj po konobaru; red se otvara u listu smjena sa razlikom u predaji.
class _Workers extends StatelessWidget {
  const _Workers({required this.workers});

  final List<WorkerReport> workers;

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) return _WorkerCards(workers: workers);
    const head = TextStyle(
      color: SankoColors.muted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    final error = Theme.of(context).colorScheme.error;
    Widget cell(String text, double width, {TextStyle? style}) => SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: (style ?? const TextStyle()).copyWith(
          fontFeatures: tabularFigures,
        ),
      ),
    );
    return _Panel(
      title: 'Po konobaru',
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('Konobar', style: head)),
              cell('Smjena', 70, style: head),
              cell('Promet', 130, style: head),
              cell('S manjkom', 90, style: head),
              cell('Manjak', 120, style: head),
              cell('Višak', 110, style: head),
              Tooltip(
                message:
                    'Prebrojano više nego što je moglo biti, ili potrošnja mnogo veća od uobičajene',
                child: cell('Sumnjivo brojanje', 140, style: head),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const Divider(),
          for (final w in workers)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        w.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    cell('${w.shifts.length}', 70),
                    cell(fmtMoney(w.revenue), 130),
                    cell(
                      '${w.shortShifts.length}',
                      90,
                      style: TextStyle(
                        color: w.shortShifts.isEmpty ? null : error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    cell(
                      w.shortage == 0 ? '–' : fmtMoney(w.shortage),
                      120,
                      style: TextStyle(
                        color: w.shortage == 0 ? SankoColors.muted : error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    cell(
                      w.surplus == 0 ? '–' : fmtMoney(w.surplus),
                      110,
                      style: const TextStyle(color: SankoColors.muted),
                    ),
                    cell(
                      w.anomalies == 0 ? '–' : '${w.anomalies}',
                      140,
                      style: TextStyle(
                        color: w.anomalies == 0 ? SankoColors.muted : error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                children: [
                  for (final s in w.shifts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 220,
                            child: Text(
                              '${weekdayName(s.businessDate)}, ${fmtDate(s.businessDate)}, smjena ${s.seq}',
                              style: const TextStyle(
                                color: SankoColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          cell('za predati ${fmtMoney(s.total)}', 190),
                          cell(
                            s.difference == null
                                ? 'bez predaje'
                                : s.difference! < 0
                                ? 'manjak ${fmtMoney(-s.difference!)}'
                                : s.difference! > 0
                                ? 'višak ${fmtMoney(s.difference!)}'
                                : 'tačno',
                            160,
                            style: TextStyle(
                              color: (s.difference ?? 0) < 0
                                  ? error
                                  : SankoColors.muted,
                              fontWeight: (s.difference ?? 0) < 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          if (s.anomalies.isNotEmpty)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Text(
                                  'Prebrojano više: ${s.anomalies.join(', ')}',
                                  style: TextStyle(color: error, fontSize: 13),
                                ),
                              ),
                            ),
                        ],
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

/// Najprodavaniji artikli, sa udjelom u prometu šanka.
class _TopItems extends StatelessWidget {
  const _TopItems({required this.items, required this.revenue});

  final List<ItemRevenue> items;
  final int revenue;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(15).toList();
    final max = shown.isEmpty ? 0 : shown.first.amount;
    if (isCompact(context)) {
      return _TopItemCards(items: shown, max: max, revenue: revenue);
    }
    return _Panel(
      title: 'Najprodavaniji artikli',
      child: Column(
        children: [
          for (final (i, item) in shown.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${i + 1}.',
                      style: const TextStyle(color: SankoColors.muted),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: max == 0 ? 0 : item.amount / max,
                        child: Container(
                          height: 10,
                          decoration: const BoxDecoration(
                            color: SankoColors.brass,
                            borderRadius: BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '${item.qty} kom.',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: SankoColors.muted,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      fmtKm(item.amount),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      revenue == 0
                          ? ''
                          : '${(item.amount * 100 / revenue).round()} %',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: SankoColors.muted,
                        fontFeatures: tabularFigures,
                      ),
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

/// Konobari na telefonu: kartica po konobaru; dodir otvara njegove smjene.
class _WorkerCards extends StatelessWidget {
  const _WorkerCards({required this.workers});

  final List<WorkerReport> workers;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return _Panel(
      title: 'Po konobaru',
      child: Column(
        children: [
          for (final (i, w) in workers.indexed) ...[
            if (i > 0) const Divider(),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: SankoColors.navy,
                      child: Text(
                        w.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: SankoColors.brass,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        w.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      fmtKm(w.revenue),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Chip(
                        '${w.shifts.length} '
                        '${plural(w.shifts.length, 'smjena', 'smjene', 'smjena')}',
                      ),
                      _Chip(
                        w.shortage == 0
                            ? 'bez manjka'
                            : 'manjak ${fmtKm(w.shortage)} '
                                  '(${w.shortShifts.length}×)',
                        color: w.shortage == 0 ? null : error,
                      ),
                      if (w.surplus > 0) _Chip('višak ${fmtKm(w.surplus)}'),
                      if (w.anomalies > 0)
                        _Chip(
                          'sumnjivo brojanje: ${w.anomalies}',
                          color: error,
                        ),
                    ],
                  ),
                ),
                children: [
                  for (final s in w.shifts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${fmtDate(s.businessDate)}, smjena ${s.seq}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'za predati ${fmtKm(s.total)}',
                                  style: const TextStyle(
                                    color: SankoColors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                                if (s.anomalies.isNotEmpty)
                                  Text(
                                    'Prebrojano više: ${s.anomalies.join(', ')}',
                                    style: TextStyle(
                                      color: error,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            s.difference == null
                                ? 'bez predaje'
                                : s.difference! < 0
                                ? 'manjak ${fmtMoney(-s.difference!)}'
                                : s.difference! > 0
                                ? 'višak ${fmtMoney(s.difference!)}'
                                : 'tačno',
                            style: TextStyle(
                              fontSize: 13,
                              fontFeatures: tabularFigures,
                              color: (s.difference ?? 0) < 0
                                  ? error
                                  : SankoColors.muted,
                              fontWeight: (s.difference ?? 0) < 0
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
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
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SankoColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color == null ? SankoColors.paper : c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c,
          fontFeatures: tabularFigures,
        ),
      ),
    );
  }
}

/// Najprodavaniji artikli na telefonu: naziv i iznos, ispod traka udjela.
class _TopItemCards extends StatelessWidget {
  const _TopItemCards({
    required this.items,
    required this.max,
    required this.revenue,
  });

  final List<ItemRevenue> items;
  final int max;
  final int revenue;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Najprodavaniji artikli',
      child: Column(
        children: [
          for (final (i, item) in items.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${i + 1}.',
                          style: const TextStyle(color: SankoColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        fmtKm(item.amount),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const SizedBox(width: 26),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: max == 0 ? 0 : item.amount / max,
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                color: SankoColors.brass,
                                borderRadius: BorderRadius.horizontal(
                                  right: Radius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${item.qty} kom.'
                        '${revenue == 0 ? '' : ' · ${(item.amount * 100 / revenue).round()} %'}',
                        style: const TextStyle(
                          color: SankoColors.muted,
                          fontSize: 12,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
