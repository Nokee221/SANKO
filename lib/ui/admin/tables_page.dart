import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                label: const Text('Dodaj stolove'),
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

/// Dodaje jedan sto ili više njih odjednom, npr. "Sto" od 1 do 12.
class _TablesDialog extends StatefulWidget {
  const _TablesDialog();

  @override
  State<_TablesDialog> createState() => _TablesDialogState();
}

class _TablesDialogState extends State<_TablesDialog> {
  final _name = TextEditingController(text: 'Sto');
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// Nazivi stolova koji će se dodati; prazno kad unos nije potpun.
  List<String> get _names {
    final name = _name.text.trim();
    final from = int.tryParse(_from.text);
    final to = int.tryParse(_to.text) ?? from;
    if (from == null) return name.isEmpty ? [] : [name];
    if (to == null || to < from || to - from >= 100) return [];
    return [for (var n = from; n <= to; n++) name.isEmpty ? '$n' : '$name $n'];
  }

  Future<void> _save() async {
    final names = _names;
    final saved = await guard(
      context,
      () => AdminScope.of(context).addTables(names),
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final names = _names;
    final number = InputDecoration(
      counterText: '',
      labelText: 'Od',
      hintText: 'bez broja',
    );
    return AlertDialog(
      scrollable: true,
      title: const Text('Dodaj stolove'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Naziv',
                helperText: 'npr. Sto, Terasa ili Šank',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: number.copyWith(
                      labelText: 'Do',
                      hintText: 'samo jedan',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                names.isEmpty
                    ? 'Unesite naziv ili ispravan raspon brojeva.'
                    : names.length <= 4
                    ? 'Dodaje: ${names.join(', ')}'
                    : 'Dodaje ${names.length}: ${names.first}, ${names[1]} … ${names.last}',
                style: const TextStyle(color: SankoColors.muted),
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
          onPressed: names.isEmpty ? null : _save,
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}
