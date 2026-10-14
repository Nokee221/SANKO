import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'pin_screen.dart';
import 'scope.dart';

/// Prvo pokretanje na telefonu: kod lokala koji konobar dobije od gazde.
class VenueCodeScreen extends StatefulWidget {
  const VenueCodeScreen({super.key});

  @override
  State<VenueCodeScreen> createState() => _VenueCodeScreenState();
}

class _VenueCodeScreenState extends State<VenueCodeScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );
    return Scaffold(
      backgroundColor: SankoColors.navy,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Wordmark(),
                  const SizedBox(height: 28),
                  const Text(
                    'Unesite kod lokala koji ste dobili od gazde',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    cursorColor: SankoColors.brass,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                    ],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      fillColor: SankoColors.navyRaised,
                      border: field,
                      enabledBorder: field,
                      focusedBorder: field.copyWith(
                        borderSide: const BorderSide(
                          color: SankoColors.brass,
                          width: 1.5,
                        ),
                      ),
                      counterText: '',
                      hintText: 'ABC123',
                      hintStyle: const TextStyle(color: Colors.white24),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 58,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: SankoColors.brass,
                        foregroundColor: SankoColors.navy,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white38,
                      ),
                      onPressed: _code.text.trim().length == 6
                          ? () => SyncScope.of(context).setVenueCode(_code.text)
                          : null,
                      child: const Text('Dalje'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
