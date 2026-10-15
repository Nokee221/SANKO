// Telegram bot Šanka: veže razgovor za lokal kad gazda otvori link iz admin panela
// (t.me/<bot>?start=<kod>) i pritisne Start.
//
// Podešavanje (jednom): otvoriti u pregledaču
//   https://<projekat>.supabase.co/functions/v1/telegram-webhook?setup=<TELEGRAM_WEBHOOK_SECRET>
// Funkcija tada prijavi svoju adresu Telegramu i upiše bota u bazu.
// Potrebno: tajne TELEGRAM_BOT_TOKEN i TELEGRAM_WEBHOOK_SECRET; "Verify JWT" isključen.

import { createClient } from 'npm:@supabase/supabase-js@2';

const token = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
const secret = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '';
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;

const db = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
});

async function telegram(method: string, body: Record<string, unknown>) {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return response.json();
}

function text(status: number, body: string) {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}

/** Prijavljuje webhook kod Telegrama i upisuje bota i adresu funkcija u bazu. */
async function setup(): Promise<Response> {
  const functionsUrl = `${supabaseUrl}/functions/v1`;
  const me = await telegram('getMe', {});
  if (!me.ok) return text(500, `Telegram ne prihvata token: ${me.description}`);
  const hook = await telegram('setWebhook', {
    url: `${functionsUrl}/telegram-webhook`,
    secret_token: secret,
    allowed_updates: ['message'],
  });
  if (!hook.ok) return text(500, `Webhook nije postavljen: ${hook.description}`);
  const { error } = await db.rpc('telegram_configure', {
    p_bot: me.result.username,
    p_functions_url: functionsUrl,
  });
  if (error) return text(500, `Baza: ${error.message}`);
  return text(200, `Telegram je podešen: @${me.result.username}. Gazde ga sada mogu povezati u admin panelu.`);
}

Deno.serve(async (req) => {
  if (!token || secret.length < 16) {
    return text(500, 'Postavite tajne TELEGRAM_BOT_TOKEN i TELEGRAM_WEBHOOK_SECRET (bar 16 znakova).');
  }
  const url = new URL(req.url);
  if (req.method === 'GET') {
    return url.searchParams.get('setup') === secret ? setup() : text(404, 'Nije pronađeno.');
  }
  // Telegram šalje tajnu u zaglavlju; bez nje zahtjev nije od Telegrama.
  if (req.headers.get('x-telegram-bot-api-secret-token') !== secret) {
    return text(401, 'Nije dozvoljeno.');
  }

  const update = await req.json().catch(() => null);
  const msg = update?.message;
  if (!msg?.chat?.id || typeof msg.text !== 'string') return text(200, 'ok');
  const chat = msg.chat;
  const code = msg.text.match(/^\/start(?:@\w+)?\s+([0-9a-f]{32})\s*$/)?.[1];

  if (!code) {
    await telegram('sendMessage', {
      chat_id: chat.id,
      text:
        'Ovo je Šanko bot za obavještenja o smjenama. Da ga povežete sa lokalom, ' +
        'u admin panelu otvorite Obavještenja i kliknite "Poveži Telegram".',
    });
    return text(200, 'ok');
  }

  const title = chat.title ?? ([chat.first_name, chat.last_name].filter(Boolean).join(' ') || 'Telegram');
  const { data: venue, error } = await db.rpc('telegram_claim_link', {
    p_code: code,
    p_chat_id: chat.id,
    p_title: title,
  });
  await telegram('sendMessage', {
    chat_id: chat.id,
    text: error
      ? 'Povezivanje nije uspjelo. Pokušajte ponovo za minut.'
      : venue
        ? `Povezano sa lokalom ${venue}. Ovdje će stizati obavještenja kad se smjena zaključi.`
        : 'Link je istekao ili je već iskorišten. U admin panelu napravite novi.',
  });
  return text(200, 'ok');
});
