import 'package:flutter/material.dart';

import '../theme.dart';
import 'items_page.dart';
import 'obracun_page.dart';
import 'prosjek_page.dart';
import 'widgets.dart';
import 'workers_page.dart';

/// Admin panel: obračun, artikli i radnici jednog lokala.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.header, this.footer, this.venueName = ''});

  /// Naziv lokala, za dokumente kao što je PDF obračuna.
  final String venueName;

  /// Podaci o lokalu ispod naziva aplikacije.
  final Widget? header;

  /// Dno trake, npr. odjava.
  final Widget? footer;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static const _pages = [
    (Icons.table_chart_outlined, 'Obračun'),
    (Icons.insights_outlined, 'Prosjek'),
    (Icons.local_bar_outlined, 'Artikli'),
    (Icons.people_outline, 'Radnici'),
  ];

  @override
  Widget build(BuildContext context) {
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
                      Text(
                        'Šanko',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.header != null) ...[
                  const SizedBox(height: 20),
                  widget.header!,
                ],
                const SizedBox(height: 24),
                for (final (i, (icon, label)) in _pages.indexed)
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
            child: switch (_index) {
              0 => ObracunPage(venueName: widget.venueName),
              1 => const ProsjekPage(),
              2 => const ItemsPage(),
              _ => const WorkersPage(),
            },
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
