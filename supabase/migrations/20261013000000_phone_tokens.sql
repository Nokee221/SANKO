-- Telefoni konobara se više ne prijavljuju kroz Supabase Auth (anonimna prijava nije potrebna).
-- Prijava kodom lokala i PIN-om vraća tajni token za taj telefon; sve ostale funkcije
-- telefona traže taj token i same provjeravaju čija je smjena. Telefon ne čita tabele direktno.

-- ---------------------------------------------------------------------------
-- Uklanjanje starog mehanizma
-- ---------------------------------------------------------------------------

drop function public.waiter_login(text, text);
drop function public.start_shift(uuid);
drop function public.sync_shift(jsonb);

drop policy venues_select on public.venues;
drop policy workers_select on public.workers;
drop policy items_select on public.items;
drop policy shifts_select on public.shifts;
drop policy shift_lines_select on public.shift_lines;
drop policy receipts_select on public.receipts;
drop policy receipt_lines_select on public.receipt_lines;
drop policy expenses_select on public.expenses;

drop function private.session_venue();
drop function private.session_worker();

drop table private.worker_sessions;
drop table private.login_attempts;

-- ---------------------------------------------------------------------------
-- Tabele
-- ---------------------------------------------------------------------------

-- Jedan red je jedan prijavljen telefon. Čuva se samo hash tokena.
create table private.worker_sessions (
  token_hash text primary key,
  device_id text not null,
  worker_id uuid not null references public.workers (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index worker_sessions_worker_id_idx on private.worker_sessions (worker_id);
create index worker_sessions_device_id_idx on private.worker_sessions (device_id);

create table private.login_attempts (
  id bigint generated always as identity primary key,
  device_id text not null,
  venue_code text not null,
  at timestamptz not null default now()
);
create index login_attempts_device_idx on private.login_attempts (device_id, at);
create index login_attempts_code_idx on private.login_attempts (venue_code, at);

-- ---------------------------------------------------------------------------
-- Pomoćne funkcije
-- ---------------------------------------------------------------------------

create function private.token_hash(p_token text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
$$;

-- Prijava kojoj token pripada; baca grešku ako token ne važi (npr. radnik je obrisan).
create function private.require_session(p_token text)
returns private.worker_sessions
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions;
begin
  select * into v_session
  from private.worker_sessions s
  where s.token_hash = private.token_hash(coalesce(p_token, ''));
  if not found then
    raise exception 'Niste prijavljeni. Prijavite se ponovo.' using errcode = '42501';
  end if;
  return v_session;
end;
$$;

-- Cijela smjena sa stavkama, ulazima i rashodima, u obliku koji telefon čita.
create function private.shift_json(p_shift_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(s) || jsonb_build_object(
    'shift_lines', coalesce((
      select jsonb_agg(to_jsonb(l) order by l.sort_order, l.item_name)
      from public.shift_lines l where l.shift_id = s.id), '[]'::jsonb),
    'receipts', coalesce((
      select jsonb_agg(
        to_jsonb(r) || jsonb_build_object('receipt_lines', coalesce((
          select jsonb_agg(to_jsonb(rl))
          from public.receipt_lines rl where rl.receipt_id = r.id), '[]'::jsonb))
        order by r.created_at)
      from public.receipts r where r.shift_id = s.id), '[]'::jsonb),
    'expenses', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.created_at)
      from public.expenses e where e.shift_id = s.id), '[]'::jsonb)
  )
  from public.shifts s
  where s.id = p_shift_id;
$$;

-- ---------------------------------------------------------------------------
-- Funkcije za telefon (konobar)
-- ---------------------------------------------------------------------------

-- Prijava konobara. p_device_id je slučajna oznaka koju telefon napravi pri instalaciji.
-- Vraća {ok: true, token, worker, venue} ili {ok: false, error}. Greška se vraća, a ne baca,
-- da bi pogrešan pokušaj ostao zapisan.
create function public.waiter_login(p_venue_code text, p_pin text, p_device_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := upper(trim(p_venue_code));
  v_venue public.venues;
  v_worker public.workers;
  v_token text;
begin
  if length(coalesce(p_device_id, '')) < 16 then
    raise exception 'Neispravna oznaka uređaja' using errcode = '22023';
  end if;

  if (select count(*) from private.login_attempts a
      where a.device_id = p_device_id and a.at > now() - interval '15 minutes') >= 5
    or (select count(*) from private.login_attempts a
        where a.venue_code = v_code and a.at > now() - interval '15 minutes') >= 30
  then
    return jsonb_build_object(
      'ok', false,
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
    insert into private.login_attempts (device_id, venue_code) values (p_device_id, v_code);
    return jsonb_build_object('ok', false, 'error', 'Pogrešan kod lokala ili PIN.');
  end if;

  if not private.venue_is_paid(v_venue) then
    return jsonb_build_object('ok', false, 'error', 'Pretplata za ovaj lokal je istekla.');
  end if;

  -- Dva slučajna UUID-a daju token koji se ne može pogoditi.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  delete from private.login_attempts a where a.device_id = p_device_id;
  delete from private.worker_sessions s where s.device_id = p_device_id;
  insert into private.worker_sessions (token_hash, device_id, worker_id, venue_id)
  values (private.token_hash(v_token), p_device_id, v_worker.id, v_venue.id);

  return jsonb_build_object(
    'ok', true,
    'token', v_token,
    'worker', jsonb_build_object('id', v_worker.id, 'name', v_worker.name),
    'venue', jsonb_build_object('id', v_venue.id, 'name', v_venue.name)
  );
end;
$$;

-- Otvara smjenu za prijavljenog radnika i vraća je cijelu. Traži internet, jer server
-- garantuje da je u lokalu otvorena samo jedna smjena i daje početno stanje iz prethodne.
-- Ako radnik već ima otvorenu smjenu (npr. na novom telefonu), vraća nju.
create function public.start_shift(p_token text, p_shift_id uuid)
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
      return private.shift_json(v_open.id);
    end if;
    raise exception 'Smjenu još nije zaključio/la %.', v_open.worker_name using errcode = 'P0001';
  end if;

  if not private.venue_is_paid(v_venue) then
    raise exception 'Pretplata za ovaj lokal je istekla.' using errcode = 'P0001';
  end if;

  v_date := (now() at time zone v_venue.timezone)::date;
  insert into public.shifts (id, venue_id, worker_id, worker_name, business_date, seq)
  values (
    p_shift_id, v_venue.id, v_worker.id, v_worker.name, v_date,
    (select coalesce(max(s.seq), 0) + 1 from public.shifts s
     where s.venue_id = v_venue.id and s.business_date = v_date)
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

-- Vraća smjenu prijavljenog radnika, npr. da telefon preuzme artikal dodan usred smjene.
create function public.fetch_shift(p_token text, p_shift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
begin
  if not exists (
    select 1 from public.shifts s where s.id = p_shift_id and s.worker_id = v_session.worker_id
  ) then
    raise exception 'Smjena ne postoji ili nije vaša' using errcode = '42501';
  end if;
  return private.shift_json(p_shift_id);
end;
$$;

-- Telefon šalje cijelo stanje svoje smjene; poziv se može ponavljati bez štete.
-- p_shift: {id, closed_at, counts: [{item_id, closing_qty}],
--           receipts: [{id, created_at, closed_at, lines: [{item_id, qty}]}],
--           expenses: [{id, description, amount, created_at}]}
-- Kad je closed_at zadan, smjena se zaključuje i više se ne može mijenjati.
create function public.sync_shift(p_token text, p_shift jsonb)
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
begin
  select * into v_shift from public.shifts s where s.id = v_id for update;
  if not found or v_shift.worker_id <> v_session.worker_id then
    raise exception 'Smjena ne postoji ili nije vaša' using errcode = '42501';
  end if;
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

  if exists (
    select 1 from public.shift_lines sl
    where sl.shift_id = v_id and sl.kind = 'counter' and sl.closing_qty < sl.opening_qty
  ) then
    raise exception 'Brojač ne može biti manji od prethodnog stanja.' using errcode = 'P0001';
  end if;

  if v_closed_at is not null then
    if exists (
      select 1 from public.shift_lines sl where sl.shift_id = v_id and sl.closing_qty is null
    ) then
      raise exception 'Nije uneseno stanje za sve artikle.' using errcode = 'P0001';
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
      updated_at = now()
  where s.id = v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pravila pristupa: tabele sada čita samo gazda
-- ---------------------------------------------------------------------------

create policy venues_select on public.venues
  for select to authenticated using (private.is_org_admin(org_id));
create policy workers_select on public.workers
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy items_select on public.items
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy shifts_select on public.shifts
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy shift_lines_select on public.shift_lines
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy receipts_select on public.receipts
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy receipt_lines_select on public.receipt_lines
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy expenses_select on public.expenses
  for select to authenticated using (private.is_venue_admin(venue_id));

-- ---------------------------------------------------------------------------
-- Dozvole
-- ---------------------------------------------------------------------------

revoke execute on function
  private.token_hash(text),
  private.require_session(text),
  private.shift_json(uuid)
from public;

-- Telefon nema Supabase nalog, pa ove funkcije poziva kao anon; štiti ih token.
revoke execute on function public.waiter_login(text, text, text) from public;
revoke execute on function public.start_shift(text, uuid) from public;
revoke execute on function public.fetch_shift(text, uuid) from public;
revoke execute on function public.sync_shift(text, jsonb) from public;
grant execute on function public.waiter_login(text, text, text) to anon, authenticated;
grant execute on function public.start_shift(text, uuid) to anon, authenticated;
grant execute on function public.fetch_shift(text, uuid) to anon, authenticated;
grant execute on function public.sync_shift(text, jsonb) to anon, authenticated;
