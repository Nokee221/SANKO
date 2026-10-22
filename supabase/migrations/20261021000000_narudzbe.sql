-- Uloge radnika (konobar, šank), stolovi lokala i narudžbe koje konobar kuca za stolom,
-- a šank ih vidi, otvara i označava kao gotove.

-- ---------------------------------------------------------------------------
-- Uloga radnika
-- ---------------------------------------------------------------------------

-- Konobar kuca narudžbe i vodi knjigu šanka; šank samo prima narudžbe.
alter table public.workers
  add column role text not null default 'konobar' check (role in ('konobar', 'sank'));

-- Gazda pri dodavanju ili izmjeni radnika bira i ulogu; null ostavlja postojeću.
drop function public.admin_save_worker(uuid, text, text, uuid);
create function public.admin_save_worker(
  p_venue_id uuid,
  p_name text,
  p_pin text default null,
  p_worker_id uuid default null,
  p_role text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := p_worker_id;
begin
  if not private.is_venue_admin(p_venue_id) then
    raise exception 'Nemate pristup ovom lokalu' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Unesite ime radnika.' using errcode = 'P0001';
  end if;
  if p_role is not null and p_role not in ('konobar', 'sank') then
    raise exception 'Nepoznata uloga radnika.' using errcode = 'P0001';
  end if;
  if p_pin is null and v_id is null then
    raise exception 'Unesite PIN.' using errcode = 'P0001';
  end if;
  if p_pin is not null then
    if p_pin !~ '^\d{4}$' then
      raise exception 'PIN mora imati tačno 4 cifre.' using errcode = 'P0001';
    end if;
    if exists (
      select 1
      from public.workers w
      join private.worker_secrets s on s.worker_id = w.id
      where w.venue_id = p_venue_id
        and w.active
        and w.id is distinct from v_id
        and s.pin_hash = extensions.crypt(p_pin, s.pin_hash)
    ) then
      raise exception 'Taj PIN već koristi drugi radnik.' using errcode = 'P0001';
    end if;
  end if;

  if v_id is null then
    insert into public.workers (venue_id, name, role)
    values (p_venue_id, trim(p_name), coalesce(p_role, 'konobar'))
    returning id into v_id;
  else
    update public.workers w
    set name = trim(p_name), role = coalesce(p_role, w.role)
    where w.id = v_id and w.venue_id = p_venue_id and w.active;
    if not found then
      raise exception 'Radnik ne postoji.' using errcode = 'P0002';
    end if;
    -- Promjena uloge odjavljuje radnika, da telefon otvori pravi ekran.
    if p_role is not null then
      delete from private.worker_sessions s where s.worker_id = v_id;
    end if;
  end if;

  if p_pin is not null then
    insert into private.worker_secrets (worker_id, pin_hash)
    values (v_id, extensions.crypt(p_pin, extensions.gen_salt('bf')))
    on conflict (worker_id) do update set pin_hash = excluded.pin_hash;
    -- Novi PIN odjavljuje radnika sa svih telefona.
    delete from private.worker_sessions s where s.worker_id = v_id;
  end if;

  return v_id;
end;
$$;

revoke execute on function public.admin_save_worker(uuid, text, text, uuid, text) from public, anon;
grant execute on function public.admin_save_worker(uuid, text, text, uuid, text) to authenticated;

-- Prijava telefona sada vraća i ulogu radnika.
create or replace function public.waiter_login(p_venue_code text, p_pin text, p_device_id text)
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
    'worker', jsonb_build_object('id', v_worker.id, 'name', v_worker.name, 'role', v_worker.role),
    'venue', jsonb_build_object('id', v_venue.id, 'name', v_venue.name)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Stolovi
-- ---------------------------------------------------------------------------

-- Stolove unosi gazda; lokal bez stolova kuca narudžbe samo sa rednim brojem.
create table public.venue_tables (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index venue_tables_venue_id_idx on public.venue_tables (venue_id, sort_order);

alter table public.venue_tables enable row level security;
create policy venue_tables_select on public.venue_tables
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy venue_tables_insert on public.venue_tables
  for insert to authenticated with check (private.is_venue_admin(venue_id));
create policy venue_tables_update on public.venue_tables
  for update to authenticated
  using (private.is_venue_admin(venue_id)) with check (private.is_venue_admin(venue_id));

-- ---------------------------------------------------------------------------
-- Narudžbe
-- ---------------------------------------------------------------------------

-- Oznaku narudžbe pravi telefon, pa ponovljeno slanje (slaba mreža) ne pravi duplikat.
-- Naziv stola, ime konobara, naziv i cijena artikla se kopiraju, da kasnije promjene
-- ne mijenjaju stare narudžbe.
create table public.orders (
  id uuid primary key,
  venue_id uuid not null references public.venues (id) on delete cascade,
  business_date date not null,
  number integer not null,
  worker_id uuid references public.workers (id) on delete set null,
  worker_name text not null,
  table_id uuid references public.venue_tables (id) on delete set null,
  table_name text,
  note text,
  created_at timestamptz not null default now(),
  done_at timestamptz,
  done_by uuid references public.workers (id) on delete set null,
  unique (venue_id, business_date, number)
);
create index orders_open_idx on public.orders (venue_id, created_at) where done_at is null;
create index orders_worker_idx on public.orders (worker_id, created_at);

create table public.order_lines (
  order_id uuid not null references public.orders (id) on delete cascade,
  item_id uuid not null references public.items (id),
  item_name text not null,
  price integer not null,
  qty integer not null check (qty > 0 and qty <= 999),
  sort_order integer not null default 0,
  primary key (order_id, item_id)
);

alter table public.orders enable row level security;
alter table public.order_lines enable row level security;
create policy orders_select on public.orders
  for select to authenticated using (private.is_venue_admin(venue_id));
create policy order_lines_select on public.order_lines
  for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and private.is_venue_admin(o.venue_id)
  ));

-- Narudžba sa stavkama, u obliku koji telefon čita.
create function private.order_json(p_order public.orders)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_order.id,
    'number', p_order.number,
    'worker_id', p_order.worker_id,
    'worker_name', p_order.worker_name,
    'table_name', p_order.table_name,
    'note', p_order.note,
    'created_at', p_order.created_at,
    'done_at', p_order.done_at,
    'lines', coalesce((
      select jsonb_agg(
        jsonb_build_object('item_id', l.item_id, 'name', l.item_name, 'price', l.price, 'qty', l.qty)
        order by l.sort_order, l.item_name)
      from public.order_lines l
      where l.order_id = p_order.id
    ), '[]'::jsonb)
  );
$$;

-- Artikli i stolovi za kucanje narudžbe.
create function public.waiter_menu(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
begin
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id, 'name', i.name, 'kind', i.kind, 'price', i.price,
          'sort_order', i.sort_order, 'image_id', i.image_id)
        order by i.sort_order, i.name)
      from public.items i
      where i.venue_id = v_session.venue_id and i.active
    ), '[]'::jsonb),
    'tables', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name) order by t.sort_order, t.name)
      from public.venue_tables t
      where t.venue_id = v_session.venue_id and t.active
    ), '[]'::jsonb)
  );
end;
$$;

-- Konobar šalje narudžbu: {id, table_id, note, lines: [{item_id, qty}]}.
-- Ako narudžba sa tom oznakom već postoji, samo je vraća.
create function public.place_order(p_token text, p_order jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
  v_id uuid := (p_order ->> 'id')::uuid;
  v_table_id uuid := nullif(p_order ->> 'table_id', '')::uuid;
  v_note text := nullif(trim(coalesce(p_order ->> 'note', '')), '');
  v_lines jsonb := coalesce(p_order -> 'lines', '[]'::jsonb);
  v_venue public.venues;
  v_worker public.workers;
  v_table public.venue_tables;
  v_date date;
  v_order public.orders;
  v_line jsonb;
  v_item public.items;
  v_qty integer;
begin
  select * into v_order from public.orders o where o.id = v_id;
  if found then
    if v_order.venue_id <> v_session.venue_id then
      raise exception 'Narudžba ne pripada ovom lokalu.' using errcode = '42501';
    end if;
    return private.order_json(v_order);
  end if;

  -- Zaključavanje reda lokala daje redne brojeve bez preklapanja.
  select * into v_venue from public.venues v where v.id = v_session.venue_id for update;
  if not private.venue_is_paid(v_venue) then
    raise exception 'Pretplata za ovaj lokal je istekla.' using errcode = 'P0001';
  end if;
  select * into v_worker from public.workers w where w.id = v_session.worker_id;
  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) = 0 then
    raise exception 'Narudžba je prazna.' using errcode = 'P0001';
  end if;
  if v_note is not null and length(v_note) > 200 then
    raise exception 'Napomena je preduga.' using errcode = 'P0001';
  end if;
  if v_table_id is not null then
    select * into v_table from public.venue_tables t
    where t.id = v_table_id and t.venue_id = v_venue.id and t.active;
    if not found then
      raise exception 'Taj sto više ne postoji. Osvježite stolove.' using errcode = 'P0001';
    end if;
  end if;

  v_date := (now() at time zone v_venue.timezone)::date;
  insert into public.orders (
    id, venue_id, business_date, number, worker_id, worker_name, table_id, table_name, note)
  values (
    v_id, v_venue.id, v_date,
    coalesce((select max(o.number) from public.orders o
              where o.venue_id = v_venue.id and o.business_date = v_date), 0) + 1,
    v_worker.id, v_worker.name, v_table.id, v_table.name, v_note)
  returning * into v_order;

  for v_line in select * from jsonb_array_elements(v_lines) loop
    v_qty := (v_line ->> 'qty')::integer;
    if v_qty is null or v_qty <= 0 or v_qty > 999 then
      raise exception 'Neispravna količina u narudžbi.' using errcode = 'P0001';
    end if;
    select * into v_item from public.items i
    where i.id = (v_line ->> 'item_id')::uuid and i.venue_id = v_venue.id and i.active;
    if not found then
      raise exception 'Artikal više ne postoji. Osvježite artikle.' using errcode = 'P0001';
    end if;
    insert into public.order_lines (order_id, item_id, item_name, price, qty, sort_order)
    values (v_order.id, v_item.id, v_item.name, v_item.price, v_qty, v_item.sort_order)
    on conflict (order_id, item_id) do update set qty = public.order_lines.qty + excluded.qty;
  end loop;

  return private.order_json(v_order);
end;
$$;

-- Za šank (p_mine = false): sve narudžbe lokala koje još nisu gotove, najstarije prve.
-- Za konobara (p_mine = true): njegove narudžbe od danas, najnovije prve.
create function public.waiter_orders(p_token text, p_mine boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
  v_venue public.venues;
begin
  select * into v_venue from public.venues v where v.id = v_session.venue_id;
  if p_mine then
    return coalesce((
      select jsonb_agg(private.order_json(o) order by o.created_at desc)
      from public.orders o
      where o.venue_id = v_venue.id
        and o.worker_id = v_session.worker_id
        and o.business_date = (now() at time zone v_venue.timezone)::date
    ), '[]'::jsonb);
  end if;
  return coalesce((
    select jsonb_agg(private.order_json(o) order by o.created_at)
    from public.orders o
    where o.venue_id = v_venue.id
      and o.done_at is null
      and o.created_at > now() - interval '1 day'
  ), '[]'::jsonb);
end;
$$;

-- Šank označava narudžbu kao gotovu, ili je vraća (p_done = false) ako je povučena greškom.
create function public.set_order_done(p_token text, p_order_id uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
begin
  update public.orders o
  set done_at = case when p_done then coalesce(o.done_at, now()) end,
      done_by = case when p_done then coalesce(o.done_by, v_session.worker_id) end
  where o.id = p_order_id and o.venue_id = v_session.venue_id;
  if not found then
    raise exception 'Narudžba ne postoji.' using errcode = 'P0002';
  end if;
end;
$$;

-- Gazda čita stolove i narudžbe i uređuje stolove; telefon sve radi preko funkcija.
revoke all on public.venue_tables, public.orders, public.order_lines from anon, authenticated;
grant select on public.venue_tables, public.orders, public.order_lines to authenticated;
grant insert (venue_id, name, sort_order) on public.venue_tables to authenticated;
grant update (name, sort_order, active) on public.venue_tables to authenticated;

revoke execute on function private.order_json(public.orders) from public, anon, authenticated;
revoke execute on function public.waiter_menu(text) from public;
revoke execute on function public.place_order(text, jsonb) from public;
revoke execute on function public.waiter_orders(text, boolean) from public;
revoke execute on function public.set_order_done(text, uuid, boolean) from public;
grant execute on function public.waiter_menu(text) to anon, authenticated;
grant execute on function public.place_order(text, jsonb) to anon, authenticated;
grant execute on function public.waiter_orders(text, boolean) to anon, authenticated;
grant execute on function public.set_order_done(text, uuid, boolean) to anon, authenticated;
