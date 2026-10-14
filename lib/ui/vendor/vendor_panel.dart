import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../vendor/vendor_api.dart';
import '../admin/widgets.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';

/// Daje vezu panela prodavca stablu; zavisni widgeti se osvježavaju nakon svake izmjene.
class VendorScope extends InheritedNotifier<VendorApi> {
  const VendorScope({super.key, required VendorApi api, required super.child})
    : super(notifier: api);

  static VendorApi of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VendorScope>()!.notifier!;
}

class VendorLoader<T> extends ScopedLoader<VendorApi, T> {
  const VendorLoader({super.key, required super.load, required super.builder});

  @override
  VendorApi sourceOf(BuildContext context) => VendorScope.of(context);
}

/// Panel superadmina (prodavca): kafići sa pretplatama i uplate.
class VendorPanel extends StatefulWidget {
  const VendorPanel({super.key, this.footer});

  /// Dno trake: prelazak na panel gazde, lozinka, odjava.
  final Widget? footer;

  @override
  State<VendorPanel> createState() => _VendorPanelState();
}

class _VendorPanelState extends State<VendorPanel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      (Icons.storefront_outlined, 'Kafići'),
      (Icons.payments_outlined, 'Uplate'),
    ];
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 252,
            color: SankoColors.navy,
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Logo(size: 44),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Šanko',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          Text(
                            'Superadmin',
                            style: TextStyle(
                              color: SankoColors.brass,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                for (final (i, (icon, label)) in pages.indexed)
                  _NavItem(
                    icon: icon,
                    label: label,
                    selected: i == _index,
                    onTap: () => setState(() => _index = i),
                  ),
                const Spacer(),
                if (widget.footer != null) widget.footer!,
              ],
            ),
          ),
          Expanded(
            child: _index == 0 ? const _CustomersPage() : const _PaymentsPage(),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? SankoColors.navyRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? SankoColors.brass : Colors.white60,
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _addMonths(DateTime d, int months) =>
    DateTime(d.year, d.month + months, d.day);

/// Privremena lozinka bez znakova koji se lako zamijene (0/O, 1/l/I).
String generatePassword() {
  const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(
    10,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

enum _Filter { all, expiringSoon, expired }

class _CustomersPage extends StatefulWidget {
  const _CustomersPage();

  @override
  State<_CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<_CustomersPage> {
  _Filter _filter = _Filter.all;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return VendorLoader<VendorOverview>(
      load: (api) => api.overview(),
      builder: (context, overview) {
        final today = _today();
        int count(SubscriptionStatus s) =>
            overview.venues.where((v) => v.status(today) == s).length;
        final query = _search.trim().toLowerCase();
        final shown = overview.venues.where((v) {
          final matchesFilter = switch (_filter) {
            _Filter.all => true,
            _Filter.expiringSoon =>
              v.status(today) == SubscriptionStatus.expiringSoon,
            _Filter.expired => v.status(today) == SubscriptionStatus.expired,
          };
          final matchesSearch =
              query.isEmpty ||
              '${v.orgName} ${v.name} ${v.code} ${v.ownerEmails.join(' ')}'
                  .toLowerCase()
                  .contains(query);
          return matchesFilter && matchesSearch;
        }).toList();
        final active = overview.venues
            .where((v) => v.status(today) != SubscriptionStatus.expired)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Kafići',
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Traži kafić, kod ili e-mail',
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Novi kafić'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          _NewCustomerDialog(price: overview.monthlyPrice),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Text(
                    '${overview.venues.length} '
                    '${plural(overview.venues.length, 'lokal', 'lokala', 'lokala')}, '
                    'aktivnih $active, mjesečno oko '
                    '${fmtKm(active * overview.monthlyPrice)}.',
                    style: const TextStyle(
                      color: SankoColors.muted,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChip(
                        label: 'Svi (${overview.venues.length})',
                        selected: _filter == _Filter.all,
                        onTap: () => setState(() => _filter = _Filter.all),
                      ),
                      _FilterChip(
                        label:
                            'Ističe uskoro (${count(SubscriptionStatus.expiringSoon)})',
                        selected: _filter == _Filter.expiringSoon,
                        onTap: () =>
                            setState(() => _filter = _Filter.expiringSoon),
                      ),
                      _FilterChip(
                        label: 'Istekli (${count(SubscriptionStatus.expired)})',
                        selected: _filter == _Filter.expired,
                        onTap: () => setState(() => _filter = _Filter.expired),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(text: 'Nema kafića za ovaj prikaz'),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final (i, v) in shown.indexed) ...[
                            if (i > 0) const Divider(),
                            _VenueRow(venue: v, price: overview.monthlyPrice),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SankoColors.navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? SankoColors.navy : SankoColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SankoColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Oznaka stanja pretplate u boji.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.venue});

  final VendorVenue venue;

  @override
  Widget build(BuildContext context) {
    final left = venue.daysLeft();
    final (color, label) = switch (venue.status()) {
      SubscriptionStatus.expired => (
        const Color(0xFFC62828),
        'Istekao ${fmtDate(venue.paidUntil)}',
      ),
      SubscriptionStatus.expiringSoon => (
        const Color(0xFFB26A00),
        left == 0
            ? 'Ističe danas'
            : 'Ističe za $left ${plural(left, 'dan', 'dana', 'dana')}',
      ),
      SubscriptionStatus.active => (
        const Color(0xFF1E7B4F),
        'Aktivan do ${fmtDate(venue.paidUntil)}',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VenueRow extends StatelessWidget {
  const _VenueRow({required this.venue, required this.price});

  final VendorVenue venue;
  final int price;

  Future<void> _lockNow(BuildContext context) async {
    final api = VendorScope.of(context);
    final ok = await confirm(
      context,
      title: 'Zaključati ${venue.name}?',
      action: 'Zaključaj',
      content: const Text(
        'Konobari se više neće moći prijaviti ni otvoriti smjenu dok ne produžite '
        'pretplatu. Gazda i dalje vidi stare podatke.',
      ),
    );
    if (!ok || !context.mounted) return;
    await guard(
      context,
      () => api.setPaidUntil(
        venue.id,
        _today().subtract(const Duration(days: 1)),
        note: 'Zaključano',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: SankoColors.muted, fontSize: 13);
    final last = venue.lastShiftAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${venue.orgName}, ${venue.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusPill(venue: venue),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  venue.ownerEmails.isEmpty
                      ? 'Bez gazde'
                      : venue.ownerEmails.join(', '),
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              venue.code,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  last == null
                      ? 'Još nije radio'
                      : 'Zadnja smjena ${fmtDate(last)}',
                  style: const TextStyle(fontSize: 13),
                ),
                Text(
                  '${venue.shifts30} '
                  '${plural(venue.shifts30, 'smjena', 'smjene', 'smjena')} u 30 dana, '
                  '${venue.workers} '
                  '${plural(venue.workers, 'radnik', 'radnika', 'radnika')}',
                  style: muted,
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ExtendDialog(venue: venue, price: price),
            ),
            child: const Text('Produži'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Još',
            onSelected: (action) => switch (action) {
              'date' => showDialog<void>(
                context: context,
                builder: (_) => _SetDateDialog(venue: venue),
              ),
              'lock' => _lockNow(context),
              _ => showDialog<void>(
                context: context,
                builder: (_) => _AddVenueDialog(venue: venue),
              ),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'date', child: Text('Postavi datum')),
              PopupMenuItem(value: 'lock', child: Text('Zaključaj odmah')),
              PopupMenuItem(
                value: 'venue',
                child: Text('Dodaj lokal ovoj firmi'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExtendDialog extends StatefulWidget {
  const _ExtendDialog({required this.venue, required this.price});

  final VendorVenue venue;
  final int price;

  @override
  State<_ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends State<_ExtendDialog> {
  int _months = 1;
  late final _amount = TextEditingController(text: fmtMoney(widget.price));
  final _note = TextEditingController();
  bool _amountEdited = false;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setMonths(int months) {
    setState(() {
      _months = months;
      if (!_amountEdited) _amount.text = fmtMoney(widget.price * months);
    });
  }

  Future<void> _save() async {
    final amount = parseMoney(_amount.text);
    if (amount == null) {
      showError(context, 'Iznos nije ispravan. Primjer: 25,00');
      return;
    }
    final api = VendorScope.of(context);
    setState(() => _busy = true);
    final saved = await guard(
      context,
      () => api.extend(widget.venue.id, _months, amount, note: _note.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final base = widget.venue.paidUntil.isBefore(today)
        ? today
        : widget.venue.paidUntil;
    return AlertDialog(
      title: Text('Produži: ${widget.venue.orgName}, ${widget.venue.name}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 mjesec')),
                ButtonSegment(value: 3, label: Text('3 mjeseca')),
                ButtonSegment(value: 6, label: Text('6 mjeseci')),
                ButtonSegment(value: 12, label: Text('12 mjeseci')),
              ],
              selected: {_months},
              showSelectedIcon: false,
              onSelectionChanged: (s) => _setMonths(s.first),
            ),
            const SizedBox(height: 12),
            Text(
              'Novo: plaćeno do ${fmtDate(_addMonths(base, _months))}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Uplaćeno',
                suffixText: 'KM',
              ),
              onChanged: (_) => _amountEdited = true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Napomena (npr. faktura 12/2026)',
              ),
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
          child: const Text('Produži'),
        ),
      ],
    );
  }
}

class _SetDateDialog extends StatefulWidget {
  const _SetDateDialog({required this.venue});

  final VendorVenue venue;

  @override
  State<_SetDateDialog> createState() => _SetDateDialogState();
}

class _SetDateDialogState extends State<_SetDateDialog> {
  late DateTime _date = widget.venue.paidUntil;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plaćeno do'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(fmtDate(_date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Razlog'),
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
          onPressed: () async {
            final api = VendorScope.of(context);
            final saved = await guard(
              context,
              () => api.setPaidUntil(widget.venue.id, _date, note: _note.text),
            );
            if (saved && context.mounted) Navigator.pop(context);
          },
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}

class _AddVenueDialog extends StatefulWidget {
  const _AddVenueDialog({required this.venue});

  final VendorVenue venue;

  @override
  State<_AddVenueDialog> createState() => _AddVenueDialogState();
}

class _AddVenueDialogState extends State<_AddVenueDialog> {
  final _name = TextEditingController();
  String? _code;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return AlertDialog(
      title: Text('Novi lokal za ${widget.venue.orgName}'),
      content: SizedBox(
        width: 380,
        child: code != null
            ? Text('Lokal je dodan. Kod za telefone konobara: $code')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Naziv lokala',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Lokal dobija mjesec dana pretplate; dalje ga produžavate kao i ostale.',
                    style: TextStyle(color: SankoColors.muted, fontSize: 13),
                  ),
                ],
              ),
      ),
      actions: [
        if (code == null) ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () async {
              final api = VendorScope.of(context);
              late String created;
              final ok = await guard(
                context,
                () async => created = await api.addVenue(
                  widget.venue.orgId,
                  _name.text,
                  _addMonths(_today(), 1),
                ),
              );
              if (ok && mounted) setState(() => _code = created);
            },
            child: const Text('Dodaj lokal'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Gotovo'),
          ),
      ],
    );
  }
}

class _NewCustomerDialog extends StatefulWidget {
  const _NewCustomerDialog({required this.price});

  final int price;

  @override
  State<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends State<_NewCustomerDialog> {
  final _org = TextEditingController();
  final _venue = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: generatePassword());
  late final _amount = TextEditingController(text: fmtMoney(widget.price));
  int _months = 1;
  bool _busy = false;
  String? _code;

  @override
  void dispose() {
    for (final c in [_org, _venue, _email, _password, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final amount = parseMoney(_amount.text);
    if (amount == null) {
      showError(context, 'Iznos nije ispravan. Primjer: 25,00');
      return;
    }
    final api = VendorScope.of(context);
    setState(() => _busy = true);
    late String code;
    final ok = await guard(
      context,
      () async => code = await api.createCustomer(
        orgName: _org.text.trim(),
        venueName: _venue.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        paidUntil: _addMonths(_today(), _months),
        amount: amount,
        note: 'Prvih $_months mj.',
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _code = code;
    });
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code != null) return _created(code);
    return AlertDialog(
      title: const Text('Novi kafić'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _org,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Naziv firme'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Naziv lokala'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail gazde'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              decoration: InputDecoration(
                labelText: 'Privremena lozinka',
                suffixIcon: IconButton(
                  tooltip: 'Nova lozinka',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _password.text = generatePassword(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1 mjesec')),
                ButtonSegment(value: 3, label: Text('3 mjeseca')),
                ButtonSegment(value: 12, label: Text('12 mjeseci')),
              ],
              selected: {_months},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _months = s.first;
                _amount.text = fmtMoney(widget.price * _months);
              }),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Uplaćeno za prvi period',
                suffixText: 'KM',
              ),
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
          onPressed: _busy ? null : _create,
          child: const Text('Otvori kafić'),
        ),
      ],
    );
  }

  /// Podaci koje prodavac predaje gazdi.
  Widget _created(String code) {
    final text =
        'Šanko, pristup za ${_org.text.trim()}, ${_venue.text.trim()}\n'
        'Admin panel: e-mail ${_email.text.trim()}, privremena lozinka ${_password.text}\n'
        'Kod lokala za telefone konobara: $code';
    return AlertDialog(
      title: const Text('Kafić je otvoren'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Predajte ove podatke gazdi. Lozinka se kasnije ne može vidjeti; '
              'gazda je mijenja nakon prve prijave.',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SankoColors.paper,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(text, style: const TextStyle(height: 1.5)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Kopiraj'),
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Gotovo'),
        ),
      ],
    );
  }
}

class _PaymentsPage extends StatelessWidget {
  const _PaymentsPage();

  Future<void> _editPrice(BuildContext context, int price) async {
    final api = VendorScope.of(context);
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _PriceDialog(price: price),
    );
    if (value == null || !context.mounted) return;
    await guard(context, () => api.setPrice(value));
  }

  @override
  Widget build(BuildContext context) {
    return VendorLoader<(VendorOverview, List<VendorPayment>)>(
      load: (api) async => (await api.overview(), await api.payments()),
      builder: (context, loaded) {
        final (overview, payments) = loaded;
        final now = DateTime.now();
        int total(bool Function(DateTime) when) => payments
            .where((p) => when(p.createdAt))
            .fold(0, (sum, p) => sum + p.amount);
        final thisMonth = total(
          (d) => d.year == now.year && d.month == now.month,
        );
        final lastMonthDate = DateTime(now.year, now.month - 1);
        final lastMonth = total(
          (d) => d.year == lastMonthDate.year && d.month == lastMonthDate.month,
        );
        final thisYear = total((d) => d.year == now.year);
        const muted = TextStyle(color: SankoColors.muted, fontSize: 13);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Uplate',
              children: [
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    'Cijena: ${fmtKm(overview.monthlyPrice)} mjesečno po lokalu',
                  ),
                  onPressed: () => _editPrice(context, overview.monthlyPrice),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _Total(
                        label: 'Ovaj mjesec',
                        amount: thisMonth,
                        highlight: true,
                      ),
                      _Total(label: 'Prošli mjesec', amount: lastMonth),
                      _Total(label: 'Ova godina', amount: thisYear),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (payments.isEmpty)
                    const EmptyState(text: 'Još nema uplata')
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final (i, p) in payments.indexed) ...[
                            if (i > 0) const Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      fmtDate(p.createdAt),
                                      style: muted,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${p.orgName}, ${p.venueName}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          '${p.months > 0 ? '${p.months} mj., ' : ''}'
                                          'plaćeno do ${fmtDate(p.paidUntilAfter)}'
                                          '${p.note == null ? '' : ', ${p.note}'}',
                                          style: muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    p.amount == 0 ? '–' : fmtKm(p.amount),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: tabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Dijalog drži svoj kontroler, da se ne uništi dok se prozor još zatvara.
class _PriceDialog extends StatefulWidget {
  const _PriceDialog({required this.price});

  final int price;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _controller = TextEditingController(text: fmtMoney(widget.price));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mjesečna cijena po lokalu'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: 'KM'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        FilledButton(
          onPressed: () {
            final value = parseMoney(_controller.text);
            if (value == null) {
              showError(context, 'Cijena nije ispravna. Primjer: 25,00');
              return;
            }
            Navigator.pop(context, value);
          },
          child: const Text('Sačuvaj'),
        ),
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({
    required this.label,
    required this.amount,
    this.highlight = false,
  });

  final String label;
  final int amount;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: highlight ? SankoColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? SankoColors.navy : SankoColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: highlight ? SankoColors.brass : SankoColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            fmtKm(amount),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              fontFeatures: tabularFigures,
              color: highlight ? Colors.white : SankoColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
