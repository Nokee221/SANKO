// Šalje gazdama na Telegram obavještenje o zaključenoj smjeni. Budi je baza (okidač
// shifts_after_close) čim se smjena zaključi. Šalje samo obavještenja koja čekaju u redu,
// pa je poziv bez štete i bez prijave: ne može poslati ništa što baza nije stavila u red.
// Potrebno: tajna TELEGRAM_BOT_TOKEN; "Verify JWT" isključen.

import { createClient } from 'npm:@supabase/supabase-js@2';

type Summary = {
  shift_id: string;
  venue_name: string;
  chat_ids: number[];
  business_date: string;
  seq: number;
  worker_name: string;
  opened_at: string;
  closed_at: string;
  closed_by_admin: boolean;
  sank: number;
  kitchen: number | null;
  expenses: number;
  cash: number | null;
  card: number | null;
  anomalies: { item_name: string; expected: number; counted: number }[];
};

/** Feninzi u zapis "1.010,00 KM". */
function km(amount: number): string {
  const abs = Math.abs(amount);
  const whole = Math.floor(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const cents = (abs % 100).toString().padStart(2, '0');
  return `${amount < 0 ? '-' : ''}${whole},${cents} KM`;
}

function time(iso: string): string {
  return new Date(iso).toLocaleTimeString('bs-BA', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Sarajevo',
  });
}

function escape(text: string): string {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

/** Tekst poruke; HTML oblik koji Telegram razumije. */
export function message(s: Summary): string {
  const [y, m, d] = s.business_date.split('-');
  const kitchen = s.kitchen ?? 0;
  const total = s.sank + kitchen - s.expenses;
  const lines = [
    `<b>${escape(s.venue_name)}: smjena ${s.seq} zaključena</b>`,
    `${escape(s.worker_name)}, ${d}.${m}.${y}. ${time(s.opened_at)}–${time(s.closed_at)}` +
      (s.closed_by_admin ? ' (zaključio gazda)' : ''),
    '',
    `Šank: ${km(s.sank)}`,
    `Kuhinja: ${km(kitchen)}`,
    `Rashod: ${km(s.expenses)}`,
    `<b>Za predati: ${km(total)}</b>`,
  ];
  if (s.cash !== null) {
    const card = s.card ?? 0;
    const difference = s.cash + card - total;
    lines.push(`Predano: ${km(s.cash + card)} (gotovina ${km(s.cash)}, kartice ${km(card)})`);
    if (difference < 0) lines.push(`⚠️ <b>MANJAK: ${km(-difference)}</b>`);
    else if (difference > 0) lines.push(`Višak: ${km(difference)}`);
    else lines.push('✅ Tačno predano');
  } else {
    lines.push('Predaja novca nije unesena.');
  }
  if (s.anomalies.length > 0) {
    lines.push('');
    lines.push('⚠️ <b>Prebrojano više nego što je moglo biti:</b>');
    for (const a of s.anomalies) {
      lines.push(`• ${escape(a.item_name)}: bilo ${a.expected}, uneseno ${a.counted}`);
    }
  }
  return lines.join('\n');
}

Deno.serve(async () => {
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN');
  if (!token) return new Response('TELEGRAM_BOT_TOKEN nije postavljen', { status: 500 });

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const { data, error } = await db.rpc('notify_claim');
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0;
  for (const s of (data ?? []) as Summary[]) {
    let failure: string | null = null;
    for (const chatId of s.chat_ids) {
      const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ chat_id: chatId, text: message(s), parse_mode: 'HTML' }),
      });
      if (response.ok) continue;
      const body = await response.json().catch(() => ({}));
      // Razgovor je blokirao bota ili je obrisan: više mu se ne šalje.
      const gone =
        response.status === 403 ||
        (response.status === 400 && /chat not found/i.test(body.description ?? ''));
      if (gone) {
        await db.rpc('telegram_forget_chat', { p_chat_id: chatId });
      } else {
        failure = `${response.status} ${body.description ?? ''}`.trim();
      }
    }
    await db.rpc('notify_done', { p_shift_id: s.shift_id, p_error: failure });
    if (!failure) sent++;
  }
  return new Response(JSON.stringify({ sent }), { headers: { 'Content-Type': 'application/json' } });
});
