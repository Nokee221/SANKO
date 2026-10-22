import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../common.dart';
import 'narudzba_screen.dart';
import 'sank_screen.dart';
import 'waiter_gate.dart';

/// Prvi ekran nakon prijave: šank vidi narudžbe, konobar bira narudžbu ili obračun.
class WorkerHome extends StatelessWidget {
  const WorkerHome({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    if (worker.role == WorkerRole.sank) return SankScreen(worker: worker);
    return Scaffold(
      body: Column(
        children: [
          WaiterHeader(name: worker.name),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(
                  children: [
                    ModeTile(
                      title: 'NARUDŽBA',
                      subtitle: 'Kucanje za stolom, šalje se na šank',
                      icon: Icons.receipt_long_outlined,
                      color: ModeColors.narudzba,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NarudzbaScreen(worker: worker),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ModeTile(
                      title: 'OBRAČUN',
                      subtitle: 'Ulaz, rashod, stanje i predaja',
                      icon: Icons.calculate_outlined,
                      color: ModeColors.stanje,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WaiterGate(worker: worker),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
