import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Kvadratić artikla. Kad je vrijednost unesena, cijeli kvadratić poprimi boju unosa.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.name,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.image,
    this.value,
    this.note,
  });

  final String name;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Slika artikla; bez nje kvadratić ima samo naziv.
  final Uint8List? image;

  /// Uneseni broj kao tekst; null znači da još nije uneseno.
  final String? value;

  /// Sitna napomena dok nije uneseno, npr. ranije primljena količina.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final entered = value != null;
    final title = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        height: 1.15,
        color: entered ? Colors.white : SankoColors.ink,
      ),
    );
    const check = Icon(Icons.check_circle, color: Colors.white, size: 18);

    return Material(
      color: entered ? color : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: entered ? color : SankoColors.line),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image == null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    if (entered) check,
                  ],
                )
              else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.memory(
                        image!,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        // Slika se dekodira u veličini prikaza, a ne u punoj.
                        cacheWidth: 126,
                        gaplessPlayback: true,
                      ),
                    ),
                    const Spacer(),
                    if (entered) check,
                  ],
                ),
                const SizedBox(height: 7),
                title,
              ],
              const Spacer(),
              Text(
                value ?? note ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: entered ? 24 : 12,
                  height: 1.1,
                  fontWeight: entered ? FontWeight.w800 : FontWeight.w400,
                  letterSpacing: entered ? -0.5 : 0,
                  fontFeatures: tabularFigures,
                  color: entered ? Colors.white : SankoColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
