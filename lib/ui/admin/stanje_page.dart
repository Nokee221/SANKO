import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../format.dart';
import '../theme.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Koliko je čega ostalo nakon zadnje zaključene smjene.
class StanjePage extends StatelessWidget {
  const StanjePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Stanje',
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
          child: AdminLoader<PreviousStock>(
            load: (data) => data.previousStock(),
            builder: (context, stock) {
              if (stock.rows.isEmpty) {
                return const EmptyState(text: 'Još nema artikala.');
              }
              final shift = stock.shift;
              return ListView(
                padding: pagePadding(context),
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shift == null
                                ? 'Još nema zaključene smjene; prikazano je početno stanje.'
                                : 'Ostalo nakon smjene ${shift.seq}, ${shift.workerName} · '
                                      '${weekdayName(shift.businessDate)}, ${fmtDate(shift.businessDate)}'
                                      '${shift.closedAt == null ? '' : ' u ${fmtTime(shift.closedAt!)}'}',
                            style: const TextStyle(
                              color: SankoColors.muted,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Column(
                              children: [
                                for (final (i, r) in stock.rows.indexed) ...[
                                  if (i > 0) const Divider(),
                                  _Row(row: r),
                                ],
                              ],
                            ),
                          ),
                        ],
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

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final StockRow row;

  @override
  Widget build(BuildContext context) {
    final grams = row.kind == ItemKind.counter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              row.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                grams ? fmtGrams(row.qty) : '${row.qty}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                  color: row.qty <= 0
                      ? Theme.of(context).colorScheme.error
                      : SankoColors.ink,
                ),
              ),
              if (grams && row.portion > 1)
                Text(
                  'oko ${row.qty ~/ row.portion} porcija',
                  style: const TextStyle(
                    color: SankoColors.muted,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
