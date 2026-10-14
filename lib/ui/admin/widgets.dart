import 'package:flutter/material.dart';

import '../theme.dart';

/// Znak aplikacije (šoljica u krugu).
class Logo extends StatelessWidget {
  const Logo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Naslov stranice admin panela, sa kontrolama desno od njega.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.children = const []});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 30,
      height: 1.1,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: SankoColors.ink,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // U uskom prozoru kontrole idu u red ispod naslova.
          if (constraints.maxWidth < 700 && children.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: style),
                const SizedBox(height: 14),
                Row(children: children),
              ],
            );
          }
          return Row(
            children: [
              Text(title, style: style),
              const SizedBox(width: 28),
              ...children,
            ],
          );
        },
      ),
    );
  }
}

/// Mala oznaka uz stavku, npr. vrsta artikla.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: SankoColors.paper,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: SankoColors.line),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: SankoColors.muted,
        ),
      ),
    );
  }
}

/// Prazno stanje stranice: šta nedostaje i, po potrebi, dugme za sljedeći korak.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(fontSize: 17, color: SankoColors.muted),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
