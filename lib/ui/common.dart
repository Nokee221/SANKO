import 'package:flutter/material.dart';

import '../data/errors.dart';

/// Boje po kojima konobar na prvi pogled zna u kojem je unosu.
abstract final class ModeColors {
  static const ulaz = Color(0xFF1E7B4F);
  static const rashod = Color(0xFFC2570C);
  static const stanje = Color(0xFF1D5FA8);
}

/// Učitava podatke iz izvora [S] i ponovo ih učitava nakon svake njegove promjene.
/// Dok traje novo učitavanje ostaje prikazan prethodni rezultat.
abstract class ScopedLoader<S, T> extends StatefulWidget {
  const ScopedLoader({super.key, required this.load, required this.builder});

  final Future<T> Function(S source) load;
  final Widget Function(BuildContext context, T data) builder;

  /// Izvor iz stabla. Mora ga čitati preko InheritedNotifier-a,
  /// da promjena izvora pokrene novo učitavanje.
  S sourceOf(BuildContext context);

  @override
  State<ScopedLoader<S, T>> createState() => _ScopedLoaderState<S, T>();
}

class _ScopedLoaderState<S, T> extends State<ScopedLoader<S, T>> {
  T? _data;
  bool _loaded = false;
  String? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  @override
  void didUpdateWidget(ScopedLoader<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final data = await widget.load(widget.sourceOf(context));
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _loaded = true;
        _error = null;
      });
    } on SankoException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _reload,
              child: const Text('Pokušaj ponovo'),
            ),
          ],
        ),
      );
    }
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}

/// Izvršava upis i prikazuje poruku ako bude odbijen. Vraća true ako je uspio.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on SankoException catch (e) {
    if (context.mounted) await showError(context, e.message);
    return false;
  } catch (e, stack) {
    // Neočekivana greška se ne smije progutati: korisnik mora vidjeti da akcija nije uspjela.
    debugPrint('Neočekivana greška: $e\n$stack');
    if (context.mounted) {
      await showError(
        context,
        'Akcija nije uspjela zbog neočekivane greške:\n$e',
      );
    }
    return false;
  }
}

/// Greška se prikazuje kao dijalog, da ne prekrije dugmad na dnu ekrana.
Future<void> showError(BuildContext context, String text) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      content: Text(text, textAlign: TextAlign.center),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('U redu'),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required Widget content,
  required String action,
  Color? color,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Odustani'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}
