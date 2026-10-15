import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'waiter/pin_screen.dart';

/// Ko koristi telefon: konobar (kod lokala i PIN) ili gazda (e-mail i lozinka).
enum PhoneRole { waiter, owner }

/// Daje ekranima konobara prelazak na prijavu gazde na istom telefonu.
class PhoneRoleScope extends InheritedWidget {
  const PhoneRoleScope({
    super.key,
    required this.switchTo,
    required super.child,
  });

  final ValueChanged<PhoneRole> switchTo;

  /// null izvan aplikacije za telefon (npr. u testovima ekrana konobara).
  static PhoneRoleScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhoneRoleScope>();

  @override
  bool updateShouldNotify(PhoneRoleScope oldWidget) => false;
}

/// Prvo pokretanje na telefonu: izbor između aplikacije za konobara i za gazdu.
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key, required this.onPick});

  final ValueChanged<PhoneRole> onPick;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Svijetle ikone statusne trake na tamnoj podlozi.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SankoColors.navy,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const Wordmark(),
                    const SizedBox(height: 12),
                    const Text(
                      'Ko koristi ovaj telefon?',
                      style: TextStyle(color: Colors.white70, fontSize: 17),
                    ),
                    const SizedBox(height: 32),
                    _RoleCard(
                      icon: Icons.local_bar_outlined,
                      title: 'Konobar',
                      text:
                          'Ulaz, rashod, brojanje i predaja na kraju smjene. '
                          'Prijava kodom lokala i PIN-om.',
                      onTap: () => onPick(PhoneRole.waiter),
                    ),
                    const SizedBox(height: 14),
                    _RoleCard(
                      icon: Icons.insights_outlined,
                      title: 'Gazda',
                      text:
                          'Obračun, manjkovi, izvještaji, narudžba i artikli. '
                          'Prijava e-mailom i lozinkom.',
                      onTap: () => onPick(PhoneRole.owner),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SankoColors.navyRaised,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SankoColors.brass.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: SankoColors.brass, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
