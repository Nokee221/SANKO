import 'package:flutter/material.dart';

import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'admin_session.dart';

/// Nova lozinka prijavljenog gazde, npr. umjesto privremene koju je dobio od prodavca.
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key, required this.session});

  final AdminSession session;

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text != _repeat.text) {
      showError(context, 'Lozinke se ne poklapaju.');
      return;
    }
    setState(() => _busy = true);
    final saved = await guard(
      context,
      () => widget.session.changePassword(_password.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Lozinka je promijenjena.')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Promijeni lozinku'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nova lozinka (bar 8 znakova)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Ponovi lozinku'),
              onSubmitted: (_) => _save(),
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

/// Lokal koji gazda gleda: naziv, kod za telefone i do kada je plaćeno.
class VenueCard extends StatelessWidget {
  const VenueCard({super.key, required this.session});

  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    final venue = session.venue!;
    final expired = venue.paidUntil.isBefore(dateOnly(DateTime.now()));
    const name = TextStyle(
      color: Colors.white,
      fontSize: 17,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: SankoColors.navyRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session.venues.length > 1)
            DropdownButton<String>(
              value: venue.id,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox(),
              dropdownColor: SankoColors.navyRaised,
              iconEnabledColor: Colors.white70,
              style: name,
              items: [
                for (final v in session.venues)
                  DropdownMenuItem(value: v.id, child: Text(v.name)),
              ],
              onChanged: (id) =>
                  session.select(session.venues.firstWhere((v) => v.id == id)),
            )
          else
            Text(venue.name, style: name),
          const SizedBox(height: 10),
          const Text(
            'Kod za telefone',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          Tooltip(
            message: 'Konobari ovaj kod jednom ukucaju na svom telefonu',
            child: SelectableText(
              venue.code,
              style: const TextStyle(
                color: SankoColors.brass,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            expired
                ? 'Pretplata je istekla'
                : 'Plaćeno do ${fmtDate(venue.paidUntil)}',
            style: TextStyle(
              color: expired ? SankoColors.failed : Colors.white60,
              fontSize: 12,
              fontWeight: expired ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
