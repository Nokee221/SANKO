import 'package:flutter/material.dart';

import '../../domain/stats.dart';
import '../format.dart';
import '../theme.dart';
import 'scope.dart';
import 'widgets.dart';

/// Prosječna potrošnja i ulaz po artiklu, i brojanja koja odskaču od prosjeka.
class ProsjekPage extends StatefulWidget {
  const ProsjekPage({super.key});

  @override
  State<ProsjekPage> createState() => _ProsjekPageState();
}

class _ProsjekPageState extends State<ProsjekPage> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Prosjek',
          children: [
            for (final days in const [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _PeriodChip(
                  label: 'Zadnjih $days dana',
                  selected: _days == days,
                  onTap: () => setState(() => _days = days),
                ),
              ),
          ],
        ),
        Expanded(
          child: AdminLoader<(ItemStats, List<StockLevel>)>(
            load: (data) async => (
              ItemStats.compute(
                await data.statLines(
                  today.subtract(Duration(days: _days - 1)),
                  today,
                ),
              ),
              await data.currentStock(),
            ),
            builder: (context, loaded) {
              final (stats, stock) = loaded;
              final forecasts = forecastStock(stock, stats);
              if (stats.shifts == 0) {
                return const EmptyState(
                  text: 'U ovom periodu nema zaključenih smjena',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Text(
                    'Zadnjih $_days dana: ${stats.days} '
                    '${plural(stats.days, 'dan', 'dana', 'dana')} rada, '
                    '${stats.shifts} ${plural(stats.shifts, 'zaključena smjena', 'zaključene smjene', 'zaključenih smjena')}.',
                    style: const TextStyle(
                      color: SankoColors.muted,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _LowStock(
                    forecasts: forecasts.where((f) => f.isLow).toList(),
                  ),
                  const SizedBox(height: 14),
                  _Anomalies(anomalies: stats.anomalies),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: _AveragesTable(
                        items: stats.items,
                        forecasts: {
                          for (final f in forecasts) f.level.itemId: f,
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SankoColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Brojanja koja su vjerovatno pogrešna, najnovija prva.
class _Anomalies extends StatelessWidget {
  const _Anomalies({required this.anomalies});

  final List<CountAnomaly> anomalies;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 14);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  anomalies.isEmpty
                      ? Icons.check_circle_outline
                      : Icons.flag_outlined,
                  size: 20,
                  color: anomalies.isEmpty
                      ? const Color(0xFF1E7B4F)
                      : SankoColors.ink,
                ),
                const SizedBox(width: 10),
                Text(
                  anomalies.isEmpty
                      ? 'Nema neobičnih brojanja u ovom periodu'
                      : 'Moguće greške u brojanju',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (anomalies.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text(
                'Smjene u kojima je utrošeno mnogo više nego inače, ili je prebrojano '
                'više nego što je moglo biti.',
                style: muted,
              ),
              const SizedBox(height: 10),
              for (final a in anomalies.take(30))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 220,
                        child: Text(
                          '${fmtDate(a.line.businessDate)}, smjena ${a.line.seq}, '
                          '${a.line.workerName}',
                          style: muted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          a.line.itemName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        a.line.consumed < 0
                            ? 'prebrojano ${-a.line.consumed} više nego što je bilo'
                            : 'utrošeno ${a.line.consumed}, inače oko '
                                  '${fmtAvg(a.expected)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Artikli kojih će uskoro nestati, prema prosječnoj dnevnoj potrošnji.
class _LowStock extends StatelessWidget {
  const _LowStock({required this.forecasts});

  final List<StockForecast> forecasts;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 14);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  forecasts.isEmpty
                      ? Icons.check_circle_outline
                      : Icons.inventory_2_outlined,
                  size: 20,
                  color: forecasts.isEmpty
                      ? const Color(0xFF1E7B4F)
                      : SankoColors.ink,
                ),
                const SizedBox(width: 10),
                Text(
                  forecasts.isEmpty
                      ? 'Zalihe su dovoljne za bar ${lowStockDays.round()} dana'
                      : 'Niska zaliha',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (forecasts.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Artikli kojih prema prosječnoj potrošnji neće biti dovoljno '
                'ni za ${lowStockDays.round()} dana.',
                style: muted,
              ),
              const SizedBox(height: 10),
              for (final f in forecasts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.level.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        stockText(f),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kratak opis zalihe: "zaliha 3, dovoljno za oko 0,6 dana".
String stockText(StockForecast f) {
  if (f.level.stock <= 0) return 'nema na zalihi';
  final days = f.daysLeft;
  if (days == null) return 'zaliha ${f.level.stock}';
  return 'zaliha ${f.level.stock}, dovoljno za oko ${fmtAvg(days)} '
      '${plural(days.floor(), 'dan', 'dana', 'dana')}';
}

class _AveragesTable extends StatelessWidget {
  const _AveragesTable({required this.items, required this.forecasts});

  final List<ItemAverage> items;
  final Map<String, StockForecast> forecasts;

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            s,
            style: style,
            textAlign: right ? TextAlign.right : TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: SankoColors.line),
        ),
        columnWidths: const {0: FlexColumnWidth(2.2)},
        defaultColumnWidth: const FlexColumnWidth(),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: SankoColors.paper),
            children: [
              cell('Artikal', style: header, right: false),
              cell('Po danu', style: header),
              cell('Po smjeni', style: header),
              cell('Najviše u smjeni', style: header),
              cell('Ulaz po danu', style: header),
              cell('Utrošeno ukupno', style: header),
              cell('Primljeno ukupno', style: header),
              cell('Zaliha sada', style: header),
              cell('Dovoljno za (dana)', style: header),
            ],
          ),
          for (final i in items)
            TableRow(
              decoration: forecasts[i.itemId]?.isLow ?? false
                  ? BoxDecoration(
                      color: SankoColors.waiting.withValues(alpha: 0.18),
                    )
                  : null,
              children: [
                cell(
                  i.name,
                  right: false,
                  style: number.copyWith(fontWeight: FontWeight.w700),
                ),
                cell(
                  fmtAvg(i.perDay),
                  style: number.copyWith(fontWeight: FontWeight.w700),
                ),
                cell(fmtAvg(i.perShift)),
                cell('${i.maxShift}'),
                cell(i.received == 0 ? '–' : fmtAvg(i.receivedPerDay)),
                cell('${i.consumed}'),
                cell(i.received == 0 ? '–' : '${i.received}'),
                cell('${forecasts[i.itemId]?.level.stock ?? '–'}'),
                cell(
                  forecasts[i.itemId]?.daysLeft == null
                      ? '–'
                      : fmtAvg(forecasts[i.itemId]!.daysLeft!),
                  style: forecasts[i.itemId]?.isLow ?? false
                      ? number.copyWith(fontWeight: FontWeight.w800)
                      : number,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
