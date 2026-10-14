// Otvara novog kupca iz panela prodavca: pravi nalog gazde sa privremenom lozinkom,
// pa firmu i prvi lokal. Nalog može napraviti samo ključ servera, zato ovo ne radi aplikacija.
// Poziva se samo uz prijavu prodavca; ko nije prodavac dobija grešku 403.

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Klijent sa prijavom pozivaoca: baza sama provjerava da je prodavac.
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: isVendor } = await caller.rpc('vendor_whoami');
  if (isVendor !== true) return reply(403, { error: 'Samo za prodavca.' });

  const body = await req.json().catch(() => null);
  const email = String(body?.email ?? '').trim().toLowerCase();
  const password = String(body?.password ?? '');
  const orgName = String(body?.org_name ?? '').trim();
  const venueName = String(body?.venue_name ?? '').trim();
  const paidUntil = String(body?.paid_until ?? '');
  if (!email.includes('@')) return reply(400, { error: 'Unesite ispravan e-mail gazde.' });
  if (password.length < 8) return reply(400, { error: 'Lozinka mora imati bar 8 znakova.' });
  if (!orgName || !venueName) return reply(400, { error: 'Unesite naziv firme i lokala.' });
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paidUntil)) return reply(400, { error: 'Neispravan datum pretplate.' });

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    const exists = createError?.message?.toLowerCase().includes('already');
    return reply(400, {
      error: exists ? 'Nalog sa tim e-mailom već postoji.' : `Nalog nije napravljen: ${createError?.message}`,
    });
  }

  const { data: code, error: customerError } = await caller.rpc('vendor_create_customer', {
    p_org_name: orgName,
    p_venue_name: venueName,
    p_owner_id: created.user.id,
    p_paid_until: paidUntil,
    p_amount: Number(body?.amount ?? 0),
    p_note: body?.note ?? null,
  });
  if (customerError) {
    // Bez firme nalog nema svrhe; briše se da e-mail ostane slobodan za novi pokušaj.
    await admin.auth.admin.deleteUser(created.user.id);
    return reply(400, { error: customerError.message });
  }

  return reply(200, { code });
});
