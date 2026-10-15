import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';
import 'account.dart';
import 'admin_session.dart';
import 'izvjestaj_page.dart';
import 'items_page.dart';
import 'narudzba_page.dart';
import 'obavjestenja_page.dart';
import 'obracun_page.dart';
import 'prosjek_page.dart';
import 'widgets.dart';
import 'workers_page.dart';

/// Admin panel na telefonu gazde: iste stranice kao na računaru, sa navigacijom na dnu.
class MobileAdminShell extends StatefulWidget {
  const MobileAdminShell({
    super.key,
    required this.venueName,
    this.session,
    this.onSwitchToWaiter,
  });

  final String venueName;

  /// Prijava gazde: lokal, lozinka i odjava na stranici Više; null u testovima.
  final AdminSession? session;

  /// Prebacuje telefon na aplikaciju za konobara; null kad to nije moguće.
  final VoidCallback? onSwitchToWaiter;

  @override
  State<MobileAdminShell> createState() => _MobileAdminShellState();
}

class _MobileAdminShellState extends State<MobileAdminShell> {
  int _index = 0;

  // Stranica se učitava tek kad se prvi put otvori, pa ostaje kakva je bila
  // (izabran dan, mjesec) dok se gazda vrti između kartica.
  final _opened = <int>{0};

  static const _tabs = [
    (Icons.table_chart_outlined, Icons.table_chart, 'Obračun'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Izvještaj'),
    (Icons.shopping_cart_outlined, Icons.shopping_cart, 'Narudžba'),
    (Icons.local_bar_outlined, Icons.local_bar, 'Artikli'),
    (Icons.menu, Icons.menu, 'Više'),
  ];

  Widget _page(int i) {
    final venueName = widget.venueName;
    return switch (i) {
      0 => ObracunPage(venueName: venueName),
      1 => IzvjestajPage(venueName: venueName),
      2 => NarudzbaPage(venueName: venueName),
      3 => const ItemsPage(),
      _ => _MorePage(
        session: widget.session,
        onSwitchToWaiter: widget.onSwitchToWaiter,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _opened.contains(i) ? _page(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: SankoColors.brass.withValues(alpha: 0.28),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? SankoColors.navy
                  : SankoColors.muted,
            ),
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: SankoColors.line)),
          ),
          child: NavigationBar(
            height: 68,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() {
              _index = i;
              _opened.add(i);
            }),
            destinations: [
              for (final (icon, selected, label) in _tabs)
                NavigationDestination(
                  icon: Icon(icon, color: SankoColors.muted),
                  selectedIcon: Icon(selected, color: SankoColors.navy),
                  label: label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lokal, ostale stranice, nalog i odjava.
class _MorePage extends StatelessWidget {
  const _MorePage({required this.session, this.onSwitchToWaiter});

  final AdminSession? session;
  final VoidCallback? onSwitchToWaiter;

  void _open(BuildContext context, Widget page) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => Scaffold(body: page)),
  );

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Više'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (session?.venue != null) ...[
                VenueCard(session: session!),
                const SizedBox(height: 16),
              ],
              _Group(
                children: [
                  _Tile(
                    icon: Icons.insights_outlined,
                    title: 'Prosjek',
                    subtitle: 'Potrošnja, zaliha i neobična brojanja',
                    onTap: () => _open(context, const ProsjekPage()),
                  ),
                  _Tile(
                    icon: Icons.people_outline,
                    title: 'Radnici',
                    subtitle: 'Konobari i njihovi PIN-ovi',
                    onTap: () => _open(context, const WorkersPage()),
                  ),
                  _Tile(
                    icon: Icons.notifications_outlined,
                    title: 'Obavještenja',
                    subtitle: 'Poruka na Telegram kad se smjena zaključi',
                    onTap: () => _open(context, const ObavjestenjaPage()),
                  ),
                ],
              ),
              if (session != null) ...[
                const SizedBox(height: 16),
                _Group(
                  children: [
                    _Tile(
                      icon: Icons.key_outlined,
                      title: 'Promijeni lozinku',
                      subtitle: session.email,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => PasswordDialog(session: session),
                      ),
                    ),
                    if (onSwitchToWaiter != null)
                      _Tile(
                        icon: Icons.phone_android_outlined,
                        title: 'Aplikacija za konobara',
                        subtitle: 'Ovaj telefon koristi konobar za unos smjene',
                        onTap: () async {
                          final ok = await confirm(
                            context,
                            title: 'Prebaciti na aplikaciju za konobara?',
                            action: 'Prebaci',
                            content: const Text(
                              'Bićete odjavljeni kao gazda. Konobar se prijavljuje kodom lokala i PIN-om.',
                            ),
                          );
                          if (!ok) return;
                          await session.signOut();
                          onSwitchToWaiter!();
                        },
                      ),
                    _Tile(
                      icon: Icons.logout,
                      title: 'Odjava',
                      danger: true,
                      onTap: () async {
                        final ok = await confirm(
                          context,
                          title: 'Odjaviti se?',
                          action: 'Odjavi se',
                          content: const Text(
                            'Za ponovnu prijavu trebaju e-mail i lozinka.',
                          ),
                        );
                        if (ok) await session.signOut();
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(indent: 64),
            c,
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Theme.of(context).colorScheme.error
        : SankoColors.ink;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: danger ? color.withValues(alpha: 0.1) : SankoColors.paper,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: danger ? color : SankoColors.navy),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: SankoColors.muted)),
      trailing: danger
          ? null
          : const Icon(Icons.chevron_right, color: SankoColors.muted),
      onTap: onTap,
    );
  }
}
