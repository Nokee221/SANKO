import 'package:flutter/material.dart';

/// Ispod ove širine ekrana admin panel se slaže u jednu kolonu, kao na telefonu.
const compactWidth = 700.0;

/// Uzak ekran (telefon): tabele postaju kartice, a kontrole idu jedna ispod druge.
bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < compactWidth;

/// Razmak sadržaja stranice od rubova ekrana.
EdgeInsets pagePadding(BuildContext context) => isCompact(context)
    ? const EdgeInsets.fromLTRB(16, 0, 16, 24)
    : const EdgeInsets.fromLTRB(32, 0, 32, 32);
