import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/errors.dart';
import '../common.dart';
import '../theme.dart';
import 'number_pad.dart';
import 'scope.dart';
import 'waiter_gate.dart';

/// Prijava konobara PIN-om od 4 cifre, u lokal čiji je kod unesen na ovom telefonu.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _onDigit(String d) async {
    if (_busy || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < 4) return;

    setState(() => _busy = true);
    try {
      final worker = await SyncScope.of(context).login(_pin);
      if (!mounted) return;
      setState(() {
        _pin = '';
        _busy = false;
      });
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => WaiterGate(worker: worker)));
    } on SankoException catch (e) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _changeVenue() async {
    final sync = SyncScope.of(context);
    final ok = await confirm(
      context,
      title: 'Promijeniti lokal?',
      action: 'Promijeni',
      content: const Text('Telefon će tražiti novi kod lokala.'),
    );
    if (ok) await sync.setVenueCode(null);
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Svijetle ikone statusne trake na tamnoj podlozi.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SankoColors.navy,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Wordmark(),
                    const SizedBox(height: 6),
                    Text(
                      sync.venueName ?? 'Lokal ${sync.venueCode}',
                      style: const TextStyle(
                        color: SankoColors.brass,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Unesite svoj PIN',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 11),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < _pin.length ? SankoColors.brass : null,
                              border: Border.all(
                                color: i < _pin.length
                                    ? SankoColors.brass
                                    : Colors.white38,
                                width: 1.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(
                      height: 60,
                      child: Center(
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: SankoColors.brass,
                                ),
                              )
                            : Text(
                                _error ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: SankoColors.failed,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    NumberPad(
                      dark: true,
                      onDigit: _onDigit,
                      onBackspace: () => setState(() {
                        if (_pin.isNotEmpty) {
                          _pin = _pin.substring(0, _pin.length - 1);
                        }
                      }),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _busy ? null : _changeVenue,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                      ),
                      child: Text('Promijeni lokal (${sync.venueCode})'),
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

/// Naziv aplikacije na tamnoj podlozi.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Šanko',
      style: TextStyle(
        color: Colors.white,
        fontSize: 44,
        height: 1.1,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
      ),
    );
  }
}
