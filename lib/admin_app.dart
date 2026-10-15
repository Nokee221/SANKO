import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/admin_data.dart';
import 'data/errors.dart';
import 'ui/admin/account.dart';
import 'ui/admin/admin_session.dart';
import 'ui/admin/admin_shell.dart';
import 'ui/admin/mobile_shell.dart';
import 'ui/admin/scope.dart';
import 'ui/admin/widgets.dart';
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
  const AdminApp({
    super.key,
    required this.session,
    this.mobile = false,
    this.onSwitchToWaiter,
  });

  final AdminSession session;

  /// Telefon gazde: stranice sa navigacijom na dnu umjesto bočne trake.
  final bool mobile;

  /// Na telefonu: prelazak na aplikaciju za konobara.
  final VoidCallback? onSwitchToWaiter;

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
    if (!session.signedIn) {
      return _LoginScreen(session: session, onSwitchToWaiter: onSwitchToWaiter);
    }
    if (session.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final venue = session.venue;
    if (session.isVendor) {
      if (mobile) {
        return _Message(
          text: 'Panel prodavca radi na računaru.',
          session: session,
        );
      }
      return VendorPanel(footer: _Footer(session: session));
    }
    if (venue == null) {
      return _Message(
        text: session.error ?? 'Ovaj nalog nije vezan ni za jedan lokal.',
        session: session,
      );
    }
    if (mobile) {
      return MobileAdminShell(
        key: ValueKey(venue.id),
        venueName: venue.name,
        session: session,
        onSwitchToWaiter: onSwitchToWaiter,
      );
    }
    return AdminShell(
      key: ValueKey(venue.id),
      venueName: venue.name,
      header: VenueCard(session: session),
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
                builder: (_) => PasswordDialog(session: session),
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
  const _LoginScreen({required this.session, this.onSwitchToWaiter});

  final AdminSession session;

  /// Na telefonu: konobar se ne prijavljuje e-mailom, nego kodom lokala i PIN-om.
  final VoidCallback? onSwitchToWaiter;

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
                // Na telefonu tastatura zauzme pola ekrana, pa se forma pomjera.
                child: SingleChildScrollView(
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
                        'Za vlasnike i menadžere lokala',
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
                      if (widget.onSwitchToWaiter != null) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: widget.onSwitchToWaiter,
                            child: const Text(
                              'Konobar? Prijava kodom lokala i PIN-om',
                            ),
                          ),
                        ),
                      ],
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
