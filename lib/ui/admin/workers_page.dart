import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../common.dart';
import '../theme.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Dodavanje i brisanje radnika i njihove uloge: konobar ili šank.
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
                padding: pagePadding(context),
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
                                    _RoleButton(worker: w),
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

/// Uloga radnika; klik je mijenja.
class _RoleButton extends StatelessWidget {
  const _RoleButton({required this.worker});

  final Worker worker;

  Future<void> _change(BuildContext context, WorkerRole role) async {
    if (role == worker.role) return;
    final ok = await confirm(
      context,
      title: '${worker.name}: ${role.label}?',
      action: 'Promijeni',
      content: const Text(
        'Radnik se odjavljuje sa telefona i pri sljedećoj prijavi vidi ekran nove uloge.',
      ),
    );
    if (ok && context.mounted) {
      await guard(
        context,
        () => AdminScope.of(context).setWorkerRole(worker.id, role),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<WorkerRole>(
      tooltip: 'Uloga',
      onSelected: (role) => _change(context, role),
      itemBuilder: (_) => [
        for (final role in WorkerRole.values)
          CheckedPopupMenuItem(
            value: role,
            checked: role == worker.role,
            child: Text(role.label),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tag(worker.role.label),
            const Icon(Icons.arrow_drop_down, color: SankoColors.muted),
          ],
        ),
      ),
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
  var _role = WorkerRole.konobar;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await guard(
      context,
      () => AdminScope.of(
        context,
      ).addWorker(name: _name.text, pin: _pin.text, role: _role),
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
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
                helperMaxLines: 2,
                helperText: 'PIN se kasnije ne može vidjeti; zapišite ga.',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<WorkerRole>(
                segments: const [
                  ButtonSegment(
                    value: WorkerRole.konobar,
                    label: Text('Konobar'),
                    icon: Icon(Icons.room_service_outlined),
                  ),
                  ButtonSegment(
                    value: WorkerRole.sank,
                    label: Text('Šank'),
                    icon: Icon(Icons.local_bar_outlined),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (v) => setState(() => _role = v.single),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _role == WorkerRole.konobar
                  ? 'Kuca narudžbe za stolom i vodi knjigu šanka.'
                  : 'Na šanku prima narudžbe i označava ih kao gotove.',
              style: const TextStyle(color: SankoColors.muted, fontSize: 13),
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
