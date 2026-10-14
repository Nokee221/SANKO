import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/theme.dart';

/// Zajednički okvir obje aplikacije: tema i bosanski jezik.
class SankoMaterialApp extends StatelessWidget {
  const SankoMaterialApp({super.key, required this.home, this.builder});

  final Widget home;
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Šanko',
      debugShowCheckedModeBanner: false,
      locale: const Locale('bs'),
      supportedLocales: const [Locale('bs')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: sankoTheme(),
      builder: builder,
      home: home,
    );
  }
}
