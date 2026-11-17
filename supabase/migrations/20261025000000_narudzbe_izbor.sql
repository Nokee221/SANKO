-- Izbor uz stavku narudžbe: kafa "duža, sa mlijekom", čaj "menta" i slično. Ista
-- kafa sa različitim izborom je posebna stavka; izbor ne mijenja cijenu.

alter table public.order_lines add column variant text not null default '';
alter table public.order_lines drop constraint order_lines_pkey;
alter table public.order_lines add primary key (order_id, item_id, variant);

-- Narudžba za telefon sada nosi i izbor svake stavke.
create or replace function private.order_json(p_order public.orders)
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
        jsonb_build_object(
          'item_id', l.item_id, 'name', l.item_name, 'variant', l.variant,
          'price', l.price, 'qty', l.qty)
        order by l.sort_order, l.item_name, l.variant)
      from public.order_lines l
      where l.order_id = p_order.id
    ), '[]'::jsonb)
  );
$$;

-- Konobar šalje narudžbu: {id, table_id, note, lines: [{item_id, variant, qty}]}.
create or replace function public.place_order(p_token text, p_order jsonb)
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
  v_variant text;
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
    v_variant := left(trim(coalesce(v_line ->> 'variant', '')), 120);
    if v_qty is null or v_qty <= 0 or v_qty > 999 then
      raise exception 'Neispravna količina u narudžbi.' using errcode = 'P0001';
    end if;
    select * into v_item from public.items i
    where i.id = (v_line ->> 'item_id')::uuid and i.venue_id = v_venue.id and i.active;
    if not found then
      raise exception 'Artikal više ne postoji. Osvježite artikle.' using errcode = 'P0001';
    end if;
    insert into public.order_lines (order_id, item_id, variant, item_name, price, qty, sort_order)
    values (v_order.id, v_item.id, v_variant, v_item.name, v_item.price, v_qty, v_item.sort_order)
    on conflict (order_id, item_id, variant) do update
      set qty = public.order_lines.qty + excluded.qty;
  end loop;

  return private.order_json(v_order);
end;
$$;
