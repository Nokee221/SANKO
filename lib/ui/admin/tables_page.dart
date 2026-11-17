import 'package:flutter/material.dart';

import '../../data/orders.dart';
import '../common.dart';
import '../theme.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Stolovi lokala za narudžbe. Bez stolova konobar kuca narudžbe samo sa rednim brojem.
class TablesPage extends StatelessWidget {
  const TablesPage({super.key});

  Future<void> _remove(BuildContext context, VenueTable table) async {
    final ok = await confirm(
      context,
      title: 'Obrisati ${table.name}?',
      action: 'Obriši',
      content: const Text('Stare narudžbe za ovaj sto ostaju.'),
    );
    if (ok && context.mounted) {
      await guard(context, () => AdminScope.of(context).removeTable(table.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Stolovi',
          children: [
            const Spacer(),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Dodaj sto'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _TablesDialog(),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: AdminLoader<List<VenueTable>>(
            load: (data) => data.tables(),
            builder: (context, tables) {
              if (tables.isEmpty) {
                return const EmptyState(
                  text:
                      'Nema stolova. Konobari kucaju narudžbe sa rednim brojem.\n'
                      'Dodajte stolove ako želite da šank vidi za koji sto je narudžba.',
                );
              }
              return ListView(
                padding: pagePadding(context),
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final t in tables)
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: SankoColors.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                t.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Obriši',
                                icon: const Icon(Icons.close, size: 18),
                                color: SankoColors.muted,
                                onPressed: () => _remove(context, t),
                              ),
                            ],
                          ),
                        ),
                    ],
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

/// Dodaje jedan sto; gazda upisuje naziv ručno (npr. "Sto 4" ili "Terasa").
class _TablesDialog extends StatefulWidget {
  const _TablesDialog();

  @override
  State<_TablesDialog> createState() => _TablesDialogState();
}

class _TablesDialogState extends State<_TablesDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await guard(
      context,
      () => AdminScope.of(context).addTables([_name.text]),
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novi sto'),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Naziv stola',
            hintText: 'npr. Sto 4 ili Terasa 2',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}
