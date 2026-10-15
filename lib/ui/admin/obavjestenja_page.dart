import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../common.dart';
import '../format.dart';
import '../theme.dart';
import 'layout.dart';
import 'scope.dart';
import 'widgets.dart';

/// Povezivanje Telegrama: gazda dobija poruku čim se smjena zaključi, sa iznosom,
/// manjkom i upozorenjima.
class ObavjestenjaPage extends StatelessWidget {
  const ObavjestenjaPage({super.key});

  Future<void> _link(BuildContext context) async {
    late final String url;
    final ok = await guard(
      context,
      () async => url = await AdminScope.of(context).telegramLink(),
    );
    if (!ok || !context.mounted) return;
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Povežite Telegram'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                opened
                    ? 'U Telegramu pritisnite Start. Bot će odgovoriti da je razgovor '
                          'povezan, i od tada stižu obavještenja.'
                    : 'Otvorite ovaj link na telefonu (npr. pošaljite ga sebi), pa u '
                          'Telegramu pritisnite Start:',
              ),
              const SizedBox(height: 12),
              SelectableText(
                url,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Link važi 30 minuta. Za grupni razgovor dodajte bota u grupu i '
                'pošaljite mu poruku iz linka.',
                style: TextStyle(color: SankoColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kopiraj link'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              AdminScope.of(context).refresh();
            },
            child: const Text('Gotovo'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlink(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Isključiti obavještenja?',
      action: 'Isključi',
      content: const Text(
        'Nijedan povezani Telegram razgovor više neće dobijati obavještenja za ovaj lokal.',
      ),
    );
    if (ok && context.mounted) {
      await guard(context, () => AdminScope.of(context).telegramUnlink());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(title: 'Obavještenja'),
        Expanded(
          child: AdminLoader<TelegramStatus>(
            load: (data) => data.telegramStatus(),
            builder: (context, status) => ListView(
              padding: pagePadding(context),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.send_outlined,
                                color: SankoColors.navy,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Telegram',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Kad konobar zaključi smjenu, na telefon vam stiže poruka: '
                            'šank, kuhinja, rashod, koliko je predano i da li ima manjka, '
                            'te upozorenje ako je nešto prebrojano više nego što je moglo biti.',
                            style: TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 20),
                          if (status.bot == null)
                            const Text(
                              'Telegram obavještenja još nisu podešena na serveru. '
                              'Javite se prodavcu aplikacije.',
                              style: TextStyle(color: SankoColors.muted),
                            )
                          else ...[
                            if (status.chats.isEmpty)
                              const Text(
                                'Nijedan Telegram razgovor još nije povezan.',
                                style: TextStyle(color: SankoColors.muted),
                              )
                            else
                              for (final c in status.chats)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: SankoColors.ok,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        c.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'povezano ${fmtDate(c.linkedAt)}',
                                        style: const TextStyle(
                                          color: SankoColors.muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  icon: const Icon(Icons.link, size: 18),
                                  label: Text(
                                    status.chats.isEmpty
                                        ? 'Poveži Telegram'
                                        : 'Poveži još jedan razgovor',
                                  ),
                                  onPressed: () => _link(context),
                                ),
                                if (status.chats.isNotEmpty)
                                  OutlinedButton(
                                    onPressed: () => _unlink(context),
                                    child: const Text('Isključi obavještenja'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
