import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'scope.dart';
import 'ulaz_screen.dart';

/// Rashod po stavkama: opis i iznos novca potrošenog iz kase.
class RashodScreen extends StatefulWidget {
  const RashodScreen({super.key, required this.shiftId});

  final String shiftId;

  @override
  State<RashodScreen> createState() => _RashodScreenState();
}

class _RashodScreenState extends State<RashodScreen> {
  final _description = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final amount = parseMoney(_amount.text);
    if (amount == null) {
      showError(context, 'Iznos nije ispravan. Primjer: 2,50');
      return;
    }
    final added = await guard(
      context,
      () => RepoScope.of(context).addExpense(
        widget.shiftId,
        description: _description.text,
        amount: amount,
      ),
    );
    if (!added) return;
    _description.clear();
    _amount.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ModeScaffold(
      title: 'RASHOD',
      subtitle: 'Novac potrošen iz kase',
      icon: Icons.receipt_long_outlined,
      color: ModeColors.rashod,
      body: Column(
        children: [
          Expanded(
            child: Loader<List<Expense>>(
              load: (repo) => repo.expenses(widget.shiftId),
              builder: (context, expenses) {
                if (expenses.isEmpty) {
                  return const Center(
                    child: Text(
                      'Još nema rashoda u ovoj smjeni',
                      style: TextStyle(color: SankoColors.muted, fontSize: 16),
                    ),
                  );
                }
                final total = expenses.fold(0, (sum, e) => sum + e.amount);
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Column(
                        children: [
                          for (final (i, e) in expenses.indexed) ...[
                            if (i > 0) const Divider(indent: 16, endIndent: 16),
                            ListTile(
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              title: Text(
                                e.description,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(fmtTime(e.createdAt)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fmtMoney(e.amount),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: tabularFigures,
                                      color: SankoColors.ink,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Obriši',
                                    icon: const Icon(Icons.close, size: 20),
                                    color: SankoColors.muted,
                                    onPressed: () => guard(
                                      context,
                                      () => RepoScope.of(
                                        context,
                                      ).deleteExpense(e),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Expanded(
                            child: Text(
                              'Ukupno rashod',
                              style: TextStyle(
                                color: SankoColors.muted,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            fmtKm(total),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              fontFeatures: tabularFigures,
                              color: ModeColors.rashod,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: SankoColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _description,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Opis',
                        hintText: 'npr. Konzum, mlijeko',
                        fillColor: SankoColors.paper,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Iznos',
                              suffixText: 'KM',
                              fillColor: SankoColors.paper,
                            ),
                            onSubmitted: (_) => _add(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: ModeColors.rashod,
                            ),
                            onPressed: _add,
                            icon: const Icon(Icons.add),
                            label: const Text('Dodaj'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
