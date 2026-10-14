import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';
import 'scope.dart';
import 'widgets.dart';

/// Dodavanje i brisanje radnika.
class WorkersPage extends StatelessWidget {
  const WorkersPage({super.key});

  Future<void> _remove(BuildContext context, Worker worker) async {
    final ok = await confirm(
      context,
      title: 'Obrisati radnika?',
      action: 'Obriši',
      content: Text(
        '${worker.name} se više neće moći prijaviti. Stare smjene ostaju.',
      ),
    );
    if (ok && context.mounted) {
      await guard(
        context,
        () => AdminScope.of(context).removeWorker(worker.id),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Radnici',
          children: [
            const Spacer(),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Novi radnik'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _WorkerDialog(),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: AdminLoader<List<Worker>>(
            load: (data) => data.workers(),
            builder: (context, workers) {
              if (workers.isEmpty) {
                return const EmptyState(
                  text: 'Još nema radnika. Dodajte prvog i dajte mu PIN.',
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Card(
                        child: Column(
                          children: [
                            for (final (i, w) in workers.indexed) ...[
                              if (i > 0) const Divider(),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  10,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: SankoColors.navy,
                                      child: Text(
                                        w.name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: SankoColors.brass,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        w.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Obriši',
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      color: SankoColors.muted,
                                      onPressed: () => _remove(context, w),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
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

class _WorkerDialog extends StatefulWidget {
  const _WorkerDialog();

  @override
  State<_WorkerDialog> createState() => _WorkerDialogState();
}

class _WorkerDialogState extends State<_WorkerDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await guard(
      context,
      () => AdminScope.of(context).addWorker(name: _name.text, pin: _pin.text),
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novi radnik'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ime'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN (4 cifre)',
                helperText: 'PIN se kasnije ne može vidjeti; zapišite ga.',
              ),
              onSubmitted: (_) => _save(),
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
