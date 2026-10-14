import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/admin_data.dart';
import 'data/errors.dart';
import 'ui/admin/admin_session.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/admin/scope.dart';
import 'ui/admin/widgets.dart';
import 'ui/common.dart';
import 'ui/format.dart';
import 'ui/theme.dart';
import 'ui/vendor/vendor_panel.dart';
import 'vendor/vendor_api.dart';

/// Admin panel za gazdu: radi direktno nad serverom, pa traži internet.
Future<void> runAdminApp() async {
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  runApp(AdminApp(session: AdminSession(Supabase.instance.client)));
}

/// Postavlja podatke lokala i panela superadmina iznad navigatora aplikacije.
/// Dijalozi se otvaraju kao zasebni ekrani pored glavnog, pa vide samo ono što je iznad navigatora.
Widget withAdminScopes(Widget app, {AdminData? data, VendorApi? vendorApi}) {
  var wrapped = app;
  if (data != null) wrapped = AdminScope(data: data, child: wrapped);
  if (vendorApi != null) wrapped = VendorScope(api: vendorApi, child: wrapped);
  return wrapped;
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.session});

  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final data = session.data;
        return SankoMaterialApp(
          // Podaci idu iznad navigatora, jer se dijalozi otvaraju kao zasebni ekrani
          // pored glavnog i ne vide ono što je postavljeno samo oko njega.
          builder: (context, child) => withAdminScopes(
            child!,
            data: data,
            vendorApi: session.isVendor ? session.vendorApi : null,
          ),
          home: _home(),
        );
      },
    );
  }

  Widget _home() {
    if (!session.signedIn) return _LoginScreen(session: session);
    if (session.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final venue = session.venue;
    if (session.isVendor) {
      return VendorPanel(footer: _Footer(session: session));
    }
    if (venue == null) {
      return _Message(
        text: session.error ?? 'Ovaj nalog nije vezan ni za jedan lokal.',
        session: session,
      );
    }
    return AdminShell(
      key: ValueKey(venue.id),
      venueName: venue.name,
      header: _VenueCard(session: session),
      footer: _Footer(session: session),
    );
  }
}

/// Dno bočne trake: e-mail, promjena lozinke i odjava.
class _Footer extends StatelessWidget {
  const _Footer({required this.session});

  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session.email ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: 'Promijeni lozinku',
              icon: const Icon(Icons.key_outlined, size: 20),
              color: Colors.white70,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _PasswordDialog(session: session),
              ),
            ),
            IconButton(
              tooltip: 'Odjava',
              icon: const Icon(Icons.logout, size: 20),
              color: Colors.white70,
              onPressed: session.signOut,
            ),
          ],
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.session});

  final AdminSession session;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
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
class _VenueCard extends StatelessWidget {
  const _VenueCard({required this.session});

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

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.session});

  final String text;
  final AdminSession session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyState(
        text: text,
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: session.reload,
              child: const Text('Pokušaj ponovo'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: session.signOut, child: const Text('Odjava')),
          ],
        ),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({required this.session});

  final AdminSession session;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.signIn(_email.text, _password.text);
    } on SankoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 860;
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Expanded(
              flex: 5,
              child: Container(
                color: SankoColors.navy,
                padding: const EdgeInsets.all(48),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Logo(size: 148),
                    SizedBox(height: 28),
                    Text(
                      'Šanko',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -2.5,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Digitalni obračuni',
                      style: TextStyle(
                        color: SankoColors.brass,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 6,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!wide) ...[
                        const Logo(size: 72),
                        const SizedBox(height: 20),
                      ],
                      const Text(
                        'Prijava',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: SankoColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Admin panel za vlasnike lokala',
                        style: TextStyle(
                          fontSize: 16,
                          color: SankoColors.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _email,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Lozinka'),
                        onSubmitted: (_) => _signIn(),
                      ),
                      SizedBox(
                        height: 44,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _error ?? '',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Prijavi se'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
