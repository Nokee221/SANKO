-- Svježe probne narudžbe za snimanje: nekoliko otvorenih na ekranu ŠANK i završene od
-- ranije danas na listi konobara. Pokreće se u Supabase SQL Editoru, neposredno prije
-- snimanja, poslije supabase/demo_podaci.sql. Upišite e-mail gazde ispod.
--
-- Šank boji narudžbu starije od 5 minuta crveno, pa skriptu pokrenite ponovo prije
-- svakog kadra: briše prethodne probne narudžbe i pravi nove. Prave narudžbe ostaju.
-- Brisanje: supabase/obrisi_demo_podatke.sql.

do $$
declare
  v_email constant text := 'gazda@gmail.com';
  v_open constant integer := 4;   -- otvorenih na šanku
  v_done constant integer := 14;  -- završenih ranije danas

  v_owner uuid;
  v_venue public.venues;
  v_date date;
  v_number integer;
  v_waiters uuid[];
  v_waiter_names text[];
  v_sank uuid;
  v_order uuid;
  v_hash text;
  v_created timestamptz;
  v_table public.venue_tables;
  v_k integer;
  v_w integer;
  v_notes text[] := array['bez leda', 'sa mlijekom', 'čaša vode uz kafu', 'račun odmah', 'bez šećera'];
begin
  if to_regclass('public.orders') is null then
    raise exception 'Prvo pokrenite migraciju 20261021000000_narudzbe.sql.';
  end if;

  select u.id into v_owner from auth.users u where lower(u.email) = lower(v_email);
  if v_owner is null then
    raise exception 'Nalog % ne postoji.', v_email;
  end if;
  select v.* into v_venue
  from public.venues v
  join public.org_admins a on a.org_id = v.org_id
  where a.user_id = v_owner
  order by v.created_at
  limit 1;
  if v_venue.id is null then
    raise exception 'Nalog % nije gazda nijednog lokala.', v_email;
  end if;

  select array_agg(w.id order by w.created_at), array_agg(w.name order by w.created_at)
  into v_waiters, v_waiter_names
  from public.workers w
  where w.venue_id = v_venue.id and w.active and w.role = 'konobar';
  if v_waiters is null then
    raise exception 'Lokal % nema konobara; prvo pokrenite demo_podaci.sql.', v_venue.name;
  end if;
  select w.id into v_sank
  from public.workers w
  where w.venue_id = v_venue.id and w.active and w.role = 'sank'
  order by w.created_at
  limit 1;

  delete from public.orders o where o.venue_id = v_venue.id and o.id::text like 'de3d0001-%';

  perform setseed(0.17);
  v_date := (now() at time zone v_venue.timezone)::date;
  select coalesce(max(o.number), 0) into v_number
  from public.orders o
  where o.venue_id = v_venue.id and o.business_date = v_date;

  for v_k in 1..(v_done + v_open) loop
    v_hash := md5(v_venue.id::text || v_date || v_k);
    v_order := (
      'de3d0001-' || substr(v_hash, 1, 4) || '-4' || substr(v_hash, 5, 3) || '-8' ||
      substr(v_hash, 8, 3) || '-' || substr(v_hash, 11, 12)
    )::uuid;
    -- Završene svakih ~15 minuta unazad, otvorene u zadnja 4 minuta.
    v_created := case
      when v_k <= v_done then now() - make_interval(mins => (v_done - v_k + 1) * 15 + floor(random() * 8)::integer)
      else now() - make_interval(secs => (v_done + v_open - v_k) * 70 + 20)
    end;
    v_w := 1 + v_k % array_length(v_waiters, 1);
    v_table := null;
    if random() < 0.9 then
      select * into v_table from public.venue_tables t
      where t.venue_id = v_venue.id and t.active
      order by random()
      limit 1;
    end if;
    v_number := v_number + 1;

    insert into public.orders (
      id, venue_id, business_date, number, worker_id, worker_name, table_id, table_name, note,
      created_at, done_at, done_by)
    values (
      v_order, v_venue.id, v_date, v_number, v_waiters[v_w], v_waiter_names[v_w],
      v_table.id, v_table.name,
      case when random() < 0.2 then v_notes[1 + floor(random() * array_length(v_notes, 1))::integer] end,
      v_created,
      case when v_k <= v_done then v_created + make_interval(mins => 2 + floor(random() * 5)::integer) end,
      case when v_k <= v_done then v_sank end);

    -- Jedna do četiri stavke; kafa, kapućino, kola i točeno se naručuju najčešće.
    insert into public.order_lines (order_id, item_id, item_name, price, qty, sort_order)
    select v_order, i.id, i.name, i.price,
      case when random() < 0.7 then 1 when random() < 0.7 then 2 else 3 end,
      i.sort_order
    from public.items i
    where i.venue_id = v_venue.id and i.active
    order by random() / case
      when upper(i.name) similar to '%(KAFA|KAPU|CAPU|KOLA|COLA|TOČ|TOC|KISELA)%' then 5 else 1 end
    limit 1 + floor(random() * 3.3)::integer;
  end loop;

  raise notice 'Lokal %: % otvorenih i % završenih probnih narudžbi.', v_venue.name, v_open, v_done;
end;
$$;
