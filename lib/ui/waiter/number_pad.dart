import 'package:flutter/material.dart';

import '../theme.dart';

/// Velika brojčana tastatura; koristi se za PIN i za unos količina.
class NumberPad extends StatelessWidget {
  const NumberPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.cornerLabel,
    this.onCorner,
    this.dark = false,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Dugme u donjem lijevom uglu, npr. predznak.
  final String? cornerLabel;
  final VoidCallback? onCorner;

  /// Tipke za tamnu podlogu.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final keyColor = dark
        ? Colors.white.withValues(alpha: 0.08)
        : SankoColors.paper;
    final foreground = dark ? Colors.white : SankoColors.ink;

    Widget key(Widget child, VoidCallback onTap) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          height: 62,
          child: Material(
            color: keyColor,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Center(
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: foreground,
                    fontFeatures: tabularFigures,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Widget digit(String d) => key(Text(d), () => onDigit(d));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) digit(d)]),
        Row(
          children: [
            cornerLabel == null
                ? const Expanded(child: SizedBox())
                : key(Text(cornerLabel!), onCorner!),
            digit('0'),
            key(const Icon(Icons.backspace_outlined), onBackspace),
          ],
        ),
      ],
    );
  }
}

/// Rezultat unosa količine: [value] je null kad je korisnik obrisao unos.
class QtyResult {
  const QtyResult(this.value);

  final int? value;
}

/// Otvara unos količine za jedan artikal. Vraća null ako je korisnik odustao.
Future<QtyResult?> showQtyPad(
  BuildContext context, {
  required String mode,
  required String itemName,
  required Color color,
  String? hint,
  int? initial,
  bool allowNegative = false,
}) {
  return showModalBottomSheet<QtyResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _QtyPad(
      mode: mode,
      itemName: itemName,
      color: color,
      hint: hint,
      initial: initial,
      allowNegative: allowNegative,
    ),
  );
}

class _QtyPad extends StatefulWidget {
  const _QtyPad({
    required this.mode,
    required this.itemName,
    required this.color,
    required this.hint,
    required this.initial,
    required this.allowNegative,
  });

  final String mode;
  final String itemName;
  final Color color;
  final String? hint;
  final int? initial;
  final bool allowNegative;

  @override
  State<_QtyPad> createState() => _QtyPadState();
}

class _QtyPadState extends State<_QtyPad> {
  late String _digits = widget.initial == null
      ? ''
      : widget.initial!.abs().toString();
  late bool _negative = (widget.initial ?? 0) < 0;

  // Prvi pritisak zamjenjuje postojeću vrijednost, da se ispravka ne dopisuje na stari broj.
  late bool _replaceOnNextDigit = widget.initial != null;

  void _onDigit(String d) {
    setState(() {
      if (_replaceOnNextDigit) _digits = '';
      _replaceOnNextDigit = false;
      if (_digits.length < 9) _digits = _digits == '0' ? d : _digits + d;
    });
  }

  void _onBackspace() {
    setState(() {
      _replaceOnNextDigit = false;
      if (_digits.isNotEmpty) {
        _digits = _digits.substring(0, _digits.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: widget.color,
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mode,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.itemName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                if (widget.hint != null)
                  Text(
                    widget.hint!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SankoColors.muted,
                      fontSize: 14,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    _digits.isEmpty ? '–' : '${_negative ? '-' : ''}$_digits',
                    style: TextStyle(
                      fontSize: 56,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      fontFeatures: tabularFigures,
                      color: _digits.isEmpty ? SankoColors.line : widget.color,
                    ),
                  ),
                ),
                NumberPad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  cornerLabel: widget.allowNegative ? '+/−' : null,
                  onCorner: () => setState(() => _negative = !_negative),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (widget.initial != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: SizedBox(
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pop(context, const QtyResult(null)),
                              child: const Text('Obriši unos'),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: SizedBox(
                          height: 56,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: widget.color,
                            ),
                            onPressed: _digits.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    QtyResult(
                                      int.parse(_digits) * (_negative ? -1 : 1),
                                    ),
                                  ),
                            child: const Text('Potvrdi'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
