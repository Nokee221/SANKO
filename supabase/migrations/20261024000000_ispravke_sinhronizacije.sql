-- Ispravke nakon pregleda grešaka:
-- 1. Prijava PIN-om: ograničenje i po IP adresi (oznaku uređaja šalje telefon, pa se
--    lako mijenja), i kod greške uz odbijanje, da telefon zaboravi PIN samo kad je pogrešan.
-- 2. Smjenu vodi jedan telefon: kad radnik nastavi smjenu na drugom telefonu, stari
--    telefon više ne može prepisati njene unose.
-- 3. Slanje u smjenu koju je zaključio gazda, slanje sa telefona koji više ne vodi smjenu
--    i zaključenje bez stanja za artikal koji je gazda upravo dodao vraćaju posebne kodove
--    greške (SK001, SK002, SK003), da telefon zna šta da uradi umjesto da šuti.
-- 4. Upozorenje "prebrojano više nego što je moglo biti" gleda grame, a ne porcije,
--    pa ne promakne višak manji od jedne porcije.

-- ---------------------------------------------------------------------------
-- 1. Prijava
-- ---------------------------------------------------------------------------

alter table private.login_attempts add column ip text;
create index login_attempts_ip_idx on private.login_attempts (ip, at);

-- IP adresa telefona iz zaglavlja zahtjeva; null kad je nema (npr. poziv iz SQL Editora).
create function private.request_ip()
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(trim(coalesce(
    h ->> 'cf-connecting-ip',
    h ->> 'x-real-ip',
    split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)
  )), '')
  from (select nullif(current_setting('request.headers', true), '')::jsonb as h) r;
$$;

revoke execute on function private.request_ip() from public;

-- Odbijanje sada nosi i kod: 'wrong_pin', 'locked' ili 'expired'.
create or replace function public.waiter_login(p_venue_code text, p_pin text, p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(p_venue_code));
  v_ip text := private.request_ip();
  v_venue public.venues;
  v_worker public.workers;
  v_token text;
begin
  if length(coalesce(p_device_id, '')) < 16 then
    raise exception 'Neispravna oznaka uređaja' using errcode = '22023';
  end if;

  -- Uređaj, IP adresa i lokal imaju svaki svoje ograničenje pogrešnih pokušaja.
  -- Ograničenje po IP adresi je strože od onog po lokalu, pa jedna adresa sama ne
  -- može zaključati prijavu cijelom lokalu.
  if (select count(*) from private.login_attempts a
      where a.device_id = p_device_id and a.at > now() - interval '15 minutes') >= 5
    or (v_ip is not null and (select count(*) from private.login_attempts a
        where a.ip = v_ip and a.at > now() - interval '15 minutes') >= 10)
    or (select count(*) from private.login_attempts a
        where a.venue_code = v_code and a.at > now() - interval '15 minutes') >= 30
  then
    return jsonb_build_object(
      'ok', false,
      'code', 'locked',
      'error', 'Previše pogrešnih pokušaja. Pokušajte ponovo za 15 minuta.'
    );
  end if;

  select * into v_venue from public.venues v where v.code = v_code;
  if found then
    select w.* into v_worker
    from public.workers w
    join private.worker_secrets s on s.worker_id = w.id
    where w.venue_id = v_venue.id
      and w.active
      and s.pin_hash = extensions.crypt(p_pin, s.pin_hash);
  end if;

  if v_worker.id is null then
    insert into private.login_attempts (device_id, venue_code, ip) values (p_device_id, v_code, v_ip);
    return jsonb_build_object('ok', false, 'code', 'wrong_pin', 'error', 'Pogrešan kod lokala ili PIN.');
  end if;

  if not private.venue_is_paid(v_venue) then
    return jsonb_build_object('ok', false, 'code', 'expired', 'error', 'Pretplata za ovaj lokal je istekla.');
  end if;

  -- Dva slučajna UUID-a daju token koji se ne može pogoditi.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  delete from private.login_attempts a where a.device_id = p_device_id;
  -- Stari pokušaji se čiste, da tabela ne raste bez kraja.
  delete from private.login_attempts a where a.at < now() - interval '1 day';
  delete from private.worker_sessions s where s.device_id = p_device_id;
  insert into private.worker_sessions (token_hash, device_id, worker_id, venue_id)
  values (private.token_hash(v_token), p_device_id, v_worker.id, v_venue.id);

  return jsonb_build_object(
    'ok', true,
    'token', v_token,
    'worker', jsonb_build_object('id', v_worker.id, 'name', v_worker.name, 'role', v_worker.role),
    'venue', jsonb_build_object('id', v_venue.id, 'name', v_venue.name)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Telefon koji vodi smjenu
-- ---------------------------------------------------------------------------

-- Uređaj koji vodi smjenu; null kod smjena otvorenih prije ove promjene.
alter table public.shifts add column device_id text;

-- Kad radnik nastavi svoju otvorenu smjenu na drugom telefonu, smjenu od tada vodi taj telefon.
create or replace function public.start_shift(p_token text, p_shift_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
  v_venue public.venues;
  v_worker public.workers;
  v_open public.shifts;
  v_date date;
begin
  -- Zaključavanje reda lokala reda istovremene pokušaje otvaranja smjene.
  select * into v_venue from public.venues v where v.id = v_session.venue_id for update;
  select * into v_worker from public.workers w where w.id = v_session.worker_id;

  select * into v_open from public.shifts s where s.venue_id = v_venue.id and s.closed_at is null;
  if found then
    if v_open.worker_id = v_worker.id then
      update public.shifts s set device_id = v_session.device_id, updated_at = now()
      where s.id = v_open.id and s.device_id is distinct from v_session.device_id;
      return private.shift_json(v_open.id);
    end if;
    raise exception 'Smjenu još nije zaključio/la %.', v_open.worker_name using errcode = 'P0001';
  end if;

  if not private.venue_is_paid(v_venue) then
    raise exception 'Pretplata za ovaj lokal je istekla.' using errcode = 'P0001';
  end if;

  v_date := (now() at time zone v_venue.timezone)::date;
  insert into public.shifts (id, venue_id, worker_id, worker_name, business_date, seq, device_id)
  values (
    p_shift_id, v_venue.id, v_worker.id, v_worker.name, v_date,
    (select coalesce(max(s.seq), 0) + 1 from public.shifts s
     where s.venue_id = v_venue.id and s.business_date = v_date),
    v_session.device_id
  );

  -- Početno stanje je krajnje stanje iz zadnje zaključene smjene u kojoj je artikal bio.
  insert into public.shift_lines
    (shift_id, item_id, venue_id, item_name, kind, price, sort_order, opening_qty)
  select
    p_shift_id, i.id, i.venue_id, i.name, i.kind, i.price, i.sort_order,
    coalesce(
      (select l.closing_qty
       from public.shift_lines l
       join public.shifts s on s.id = l.shift_id
       where l.item_id = i.id and s.closed_at is not null
       order by s.opened_at desc
       limit 1),
      i.initial_qty)
  from public.items i
  where i.venue_id = v_venue.id and i.active;

  return private.shift_json(p_shift_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Slanje smjene sa kodovima greške
-- ---------------------------------------------------------------------------

-- SK001: smjenu je zaključio gazda; unosi poslani poslije toga se ne primaju.
-- SK002: smjenu sada vodi drugi telefon istog radnika.
-- SK003: zaključenje bez stanja za artikal koji telefon još nema (gazda ga je upravo dodao).
create or replace function public.sync_shift(p_token text, p_shift jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
  v_id uuid := (p_shift ->> 'id')::uuid;
  v_closed_at timestamptz := (p_shift ->> 'closed_at')::timestamptz;
  v_receipts jsonb := coalesce(p_shift -> 'receipts', '[]'::jsonb);
  v_shift public.shifts;
  v_missing text;
begin
  select * into v_shift from public.shifts s where s.id = v_id for update;
  if not found or v_shift.worker_id <> v_session.worker_id then
    raise exception 'Smjena ne postoji ili nije vaša' using errcode = '42501';
  end if;
  if v_shift.closed_at is not null and v_shift.closed_by_admin then
    raise exception 'Smjenu je zaključio gazda. Unosi koji tada nisu bili poslani nisu uračunati.'
      using errcode = 'SK001';
  end if;
  if v_shift.device_id is not null and v_shift.device_id <> v_session.device_id then
    raise exception 'Ova smjena je nastavljena na drugom telefonu.' using errcode = 'SK002';
  end if;
  -- Ponovljeno slanje već zaključene smjene (npr. odgovor se izgubio) ne mijenja ništa.
  if v_shift.closed_at is not null then
    return;
  end if;

  delete from public.receipts r where r.shift_id = v_id;
  insert into public.receipts (id, shift_id, venue_id, created_at, closed_at)
  select (r ->> 'id')::uuid, v_id, v_shift.venue_id,
    (r ->> 'created_at')::timestamptz, (r ->> 'closed_at')::timestamptz
  from jsonb_array_elements(v_receipts) r;

  -- Spajanje sa stavkama smjene odbacuje artikle koji joj ne pripadaju.
  insert into public.receipt_lines (receipt_id, item_id, venue_id, qty)
  select (r ->> 'id')::uuid, sl.item_id, v_shift.venue_id, (l ->> 'qty')::integer
  from jsonb_array_elements(v_receipts) r
  cross join lateral jsonb_array_elements(coalesce(r -> 'lines', '[]'::jsonb)) l
  join public.shift_lines sl on sl.shift_id = v_id and sl.item_id = (l ->> 'item_id')::uuid;

  delete from public.expenses e where e.shift_id = v_id;
  insert into public.expenses (id, shift_id, venue_id, description, amount, created_at)
  select (e ->> 'id')::uuid, v_id, v_shift.venue_id, e ->> 'description',
    (e ->> 'amount')::integer, (e ->> 'created_at')::timestamptz
  from jsonb_array_elements(coalesce(p_shift -> 'expenses', '[]'::jsonb)) e;

  update public.shift_lines sl
  set closing_qty = (
    select c.closing_qty
    from jsonb_to_recordset(coalesce(p_shift -> 'counts', '[]'::jsonb))
      as c (item_id uuid, closing_qty integer)
    where c.item_id = sl.item_id
    limit 1
  )
  where sl.shift_id = v_id;

  if v_closed_at is not null then
    select string_agg(sl.item_name, ', ' order by sl.sort_order) into v_missing
    from public.shift_lines sl where sl.shift_id = v_id and sl.closing_qty is null;
    if v_missing is not null then
      raise exception 'Nije uneseno stanje za: %. Unesite ga i ponovo zaključite smjenu.', v_missing
        using errcode = 'SK003';
    end if;
    if exists (
      select 1 from public.receipts r
      join public.receipt_lines rl on rl.receipt_id = r.id
      where r.shift_id = v_id and r.closed_at is null
    ) then
      raise exception 'Postoji ULAZ koji nije zaključen.' using errcode = 'P0001';
    end if;
  end if;

  update public.shifts s
  -- least() preskače null, pa bi bez provjere otvorena smjena bila zaključena.
  set closed_at = case when v_closed_at is not null then least(v_closed_at, now()) end,
      kitchen = (p_shift ->> 'kitchen')::integer,
      cash = (p_shift ->> 'cash')::integer,
      card = (p_shift ->> 'card')::integer,
      updated_at = now()
  where s.id = v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Anomalija u gramima
-- ---------------------------------------------------------------------------

create or replace function private.shift_summary(p_shift public.shifts)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'shift_id', p_shift.id,
    'business_date', p_shift.business_date,
    'seq', p_shift.seq,
    'worker_id', p_shift.worker_id,
    'worker_name', p_shift.worker_name,
    'opened_at', p_shift.opened_at,
    'closed_at', p_shift.closed_at,
    'closed_by_admin', p_shift.closed_by_admin,
    'sank', coalesce(sum(t.consumed * t.price), 0),
    'kitchen', p_shift.kitchen,
    'expenses', (select coalesce(sum(e.amount), 0) from public.expenses e where e.shift_id = p_shift.id),
    'cash', p_shift.cash,
    'card', p_shift.card,
    -- Prebrojano više nego što je moglo biti, i kad je višak manji od jedne porcije.
    'anomalies', coalesce(jsonb_agg(
      jsonb_build_object('item_name', t.item_name, 'expected', t.expected, 'counted', t.closing_qty)
      order by t.sort_order) filter (where t.closing_qty > t.expected), '[]'::jsonb)
  )
  from (
    select l.item_name, l.price, l.sort_order, l.closing_qty,
      l.opening_qty + r.received as expected,
      (l.opening_qty + r.received - l.closing_qty) / l.portion as consumed
    from public.shift_lines l
    cross join lateral (
      select coalesce(sum(rl.qty), 0)::integer as received
      from public.receipt_lines rl
      join public.receipts rc on rc.id = rl.receipt_id
      where rc.shift_id = p_shift.id and rc.closed_at is not null and rl.item_id = l.item_id
    ) r
    where l.shift_id = p_shift.id and l.closing_qty is not null
  ) t;
$$;
