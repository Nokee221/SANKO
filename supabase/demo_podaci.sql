-- Probni podaci za prezentaciju: 60 dana smjena za lokal jednog gazde, da se vidi kako
-- obračun, izvještaj, prosjek i narudžba izgledaju sa pravom istorijom.
-- Pokreće se u Supabase SQL Editoru, nakon svih migracija. Upišite e-mail gazde ispod.
--
-- Pravi: tri konobara (ako lokal nema bar dva) i radnika na šanku (ako ga nema), stolove
-- (ako ih lokal nema), artikle (ako ih lokal nema), gramažu porcije kafe i nesa (gdje je
-- još 1 g), minimum za narudžbu (gdje nije postavljen) i po dvije zaključene smjene
-- dnevno, sa ulazom, rashodom, kuhinjom i predajom, i današnje smjene koje su već
-- završile. Jedan konobar povremeno ima manjak, drugi ponekad pogriješi u brojanju.
-- Ponovno pokretanje ne pravi duplikate. Brisanje: supabase/obrisi_demo_podatke.sql.
-- Svježe narudžbe za ekran ŠANK pravi supabase/demo_narudzbe.sql.
--
-- Probne smjene napravljene starom verzijom ove skripte (kafa po brojaču aparata) poslije
-- migracije 20261022000000_kafa_grami.sql daju pogrešno utrošeno: prvo ih obrišite sa
-- obrisi_demo_podatke.sql, pa pokrenite ovu skriptu ponovo.

do $$
declare
  v_email constant text := 'gazda@gmail.com';
  v_days constant integer := 60;

  v_owner uuid;
  v_venue public.venues;
  v_workers uuid[];
  v_names text[];
  v_from date := current_date - v_days;
  v_date date;
  v_dow integer;
  v_busy numeric;
  v_slot integer;
  v_w integer;
  v_shift uuid;
  v_receipt uuid;
  v_opened timestamptz;
  v_closed timestamptz;
  v_item record;
  v_open integer;
  v_received integer;
  v_used integer;
  v_closing integer;
  v_sank integer;
  v_spent integer;
  v_kitchen integer;
  v_total integer;
  v_card integer;
  v_diff integer;
  v_hash text;
  v_pin text;
  v_konobari boolean;
  v_spends text[] := array['Mlijeko', 'Led', 'Limun', 'Šećer', 'Salvete', 'Konzum, sitnice'];
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shifts' and column_name = 'cash'
  ) then
    raise exception 'Prvo pokrenite migraciju 20261020000000_predaja_izvjestaji.sql.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'workers' and column_name = 'role'
  ) then
    raise exception 'Prvo pokrenite migraciju 20261021000000_narudzbe.sql.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'items' and column_name = 'portion'
  ) then
    raise exception 'Prvo pokrenite migraciju 20261022000000_kafa_grami.sql.';
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
  if exists (
    select 1 from public.shifts s
    where s.venue_id = v_venue.id and s.id::text like 'de3d0000-%'
  ) then
    raise notice 'Probni podaci za lokal % već postoje; ništa nije promijenjeno. Za novu verziju prvo pokrenite obrisi_demo_podatke.sql.',
      v_venue.name;
    return;
  end if;
  if exists (
    select 1 from public.shifts s
    where s.venue_id = v_venue.id and s.business_date >= v_from and s.business_date < current_date
  ) then
    raise exception 'Lokal % već ima smjene u zadnjih % dana; probni podaci bi se pomiješali sa pravim.',
      v_venue.name, v_days;
  end if;

  -- Ista nasumičnost svaki put, da prezentacija uvijek izgleda isto.
  perform setseed(0.42);

  -- Konobari i radnik na šanku; PIN koji već koristi neko drugi se preskače.
  v_konobari := (
    select count(*) from public.workers w
    where w.venue_id = v_venue.id and w.active and w.role = 'konobar'
  ) < 2;
  for v_w in 1..4 loop
    continue when v_w <= 3 and not v_konobari;
    continue when v_w = 4 and exists (
      select 1 from public.workers w where w.venue_id = v_venue.id and w.active and w.role = 'sank'
    );
    continue when exists (
      select 1 from public.workers w
      where w.venue_id = v_venue.id and w.active and w.name = (array['Amra', 'Bakir', 'Dino', 'Lejla'])[v_w]
    );
    v_pin := (array['7101', '7202', '7303', '7404'])[v_w];
    if exists (
      select 1 from public.workers w
      join private.worker_secrets s on s.worker_id = w.id
      where w.venue_id = v_venue.id and w.active and s.pin_hash = extensions.crypt(v_pin, s.pin_hash)
    ) then
      raise notice 'PIN % već koristi drugi radnik; % nije dodan.', v_pin, (array['Amra', 'Bakir', 'Dino', 'Lejla'])[v_w];
      continue;
    end if;
    with w as (
      insert into public.workers (venue_id, name, role)
      values (v_venue.id, (array['Amra', 'Bakir', 'Dino', 'Lejla'])[v_w],
        case when v_w = 4 then 'sank' else 'konobar' end)
      returning id
    )
    insert into private.worker_secrets (worker_id, pin_hash)
    select w.id, extensions.crypt(v_pin, extensions.gen_salt('bf'))
    from w;
  end loop;
  select array_agg(w.id order by w.created_at), array_agg(w.name order by w.created_at)
  into v_workers, v_names
  from (
    select * from public.workers w
    where w.venue_id = v_venue.id and w.active and w.role = 'konobar'
    order by w.created_at
    limit 3
  ) w;
  if v_workers is null then
    raise exception 'Lokal % nema nijednog konobara.', v_venue.name;
  end if;

  -- Stolovi, ako ih lokal nema
  if not exists (select 1 from public.venue_tables t where t.venue_id = v_venue.id and t.active) then
    insert into public.venue_tables (venue_id, name, sort_order)
    select v_venue.id, t.name, t.ord
    from unnest(array[
      'Sto 1', 'Sto 2', 'Sto 3', 'Sto 4', 'Sto 5', 'Sto 6', 'Sto 7', 'Sto 8',
      'Terasa 1', 'Terasa 2', 'Terasa 3', 'Terasa 4', 'Šank'
    ]) with ordinality as t (name, ord);
  end if;

  -- Artikli, ako lokal još nema nijedan
  if not exists (select 1 from public.items i where i.venue_id = v_venue.id and i.active) then
    insert into public.items (venue_id, name, kind, price, initial_qty, image_id)
    select v_venue.id, d.name, d.kind::public.item_kind, d.price, d.qty,
      (select c.id from public.catalog_images c where c.name = d.name)
    from (values
      (1, 'KAFA', 'counter', 250, 145000), (2, 'NES APARAT', 'counter', 350, 50000),
      (3, 'KAPUCINO', 'stock', 350, 40), (4, 'ČAJ', 'stock', 300, 214),
      (5, 'TOPLA ČOKOLADA', 'stock', 450, 30), (6, 'JAGODA', 'stock', 350, 41),
      (7, 'JABUKA', 'stock', 350, 57), (8, 'BRESKVA', 'stock', 350, 59),
      (9, 'ĐUS', 'stock', 350, 56), (10, 'LEDENI ČAJ', 'stock', 350, 28),
      (11, 'KOLA', 'stock', 350, 77), (12, 'FANTA', 'stock', 350, 42),
      (13, 'SPRITE', 'stock', 350, 32), (14, 'TONIK', 'stock', 350, 72),
      (15, 'COCKTA', 'stock', 350, 29), (16, 'RED BULL', 'stock', 500, 23),
      (17, 'KISELA', 'stock', 250, 107), (18, 'VODA', 'stock', 250, 38),
      (19, 'LIMUN', 'stock', 350, 72), (20, 'CEDEVITA', 'stock', 300, 74),
      (21, 'HEINEKEN', 'stock', 450, 71), (22, 'STELLA', 'stock', 450, 31),
      (23, 'SARAJEVSKO', 'stock', 400, 23), (24, 'TOČENO', 'stock', 350, 60),
      (25, 'SOMERSBY', 'stock', 450, 29), (26, 'GRAŠEVINA', 'stock', 600, 26),
      (27, 'VRANAC', 'stock', 600, 12)
    ) as d (ord, name, kind, price, qty)
    order by d.ord;
  end if;

  -- Kafa i nes se vode u gramima; porcija kao u probnim artiklima aplikacije.
  update public.items i
  set portion = case when upper(i.name) like '%KAF%' then 20 else 15 end
  where i.venue_id = v_venue.id and i.active and i.kind = 'counter' and i.portion = 1;

  -- Koliko porcija artikla se proda u prosječnoj smjeni, po nazivu.
  create temp table demo_items on commit drop as
  select i.id, i.name, i.kind, i.price, i.sort_order, i.portion,
    case
      when i.kind = 'counter' and upper(i.name) like '%KAF%' then 110
      when i.kind = 'counter' then 25
      when upper(i.name) similar to '%(TOČ|TOC)%' then 14
      when upper(i.name) similar to '%(KAPU|CAPU)%' then 10
      when upper(i.name) similar to '%(KOLA|COLA)%' then 9
      when upper(i.name) similar to '%(SARAJ|HEINEKEN|PIV)%' then 8
      when upper(i.name) similar to '%(KISELA|VODA)%' then 7
      when upper(i.name) similar to '%(STELLA|BECK|CORONA|BAVARIA|RADLER|SOMERSBY)%' then 3
      when upper(i.name) similar to '%(VINA|VRANAC|GRAŠ|GRAS|GIN|JACK|CHIVAS|SMIRN|JEGER|PELIN|VILJAM|LJIVA|VIŠNJ|VISNJ|RED L)%' then 2
      else 4
    end as rate,
    -- Pivo i vino idu uveče, kafa ujutro.
    upper(i.name) similar to '%(TOČ|TOC|SARAJ|HEINEKEN|PIV|STELLA|BECK|CORONA|BAVARIA|RADLER|SOMERSBY|VINA|VRANAC|GRAŠ|GRAS|GIN|JACK|CHIVAS|SMIRN|JEGER|PELIN|VILJAM|LJIVA|VIŠNJ|VISNJ|RED L)%'
      as evening,
    coalesce(
      (select l.closing_qty from public.shift_lines l join public.shifts s on s.id = l.shift_id
       where l.item_id = i.id and s.closed_at is not null
       order by s.opened_at desc limit 1),
      i.initial_qty) as stock
  from public.items i
  where i.venue_id = v_venue.id and i.active;

  -- Minimum za narudžbu, gdje gazda još nije postavio svoj.
  update public.items i
  set min_qty = greatest(6, d.rate * 3), par_qty = greatest(12, d.rate * 9)
  from demo_items d
  where i.id = d.id and i.kind = 'stock' and i.min_qty is null;

  -- Danas samo smjene koje su već trebale završiti, i samo ako danas nema pravih smjena.
  for d in 0..v_days loop
    v_date := v_from + d;
    exit when v_date = current_date and exists (
      select 1 from public.shifts s
      where s.venue_id = v_venue.id and s.business_date = current_date
    );
    v_dow := extract(isodow from v_date);
    v_busy := case when v_dow in (5, 6) then 1.45 when v_dow = 7 then 1.15 when v_dow = 1 then 0.85 else 1 end;

    for v_slot in 1..2 loop
      -- Smjene se rotiraju među konobarima.
      v_w := 1 + (d * 2 + v_slot - 1) % coalesce(array_length(v_workers, 1), 1);
      v_shift := (
        'de3d0000-' || substr(md5(v_venue.id::text || v_date || v_slot), 1, 4) || '-4' ||
        substr(md5(v_venue.id::text || v_date || v_slot), 5, 3) || '-8' ||
        substr(md5(v_venue.id::text || v_date || v_slot), 8, 3) || '-' ||
        substr(md5(v_venue.id::text || v_date || v_slot), 11, 12)
      )::uuid;
      v_opened := ((v_date + case v_slot when 1 then time '07:00' else time '15:00' end)
        at time zone v_venue.timezone) + make_interval(mins => floor(random() * 12)::integer);
      v_closed := ((v_date + case v_slot when 1 then time '15:00' else time '23:00' end)
        at time zone v_venue.timezone) + make_interval(mins => floor(random() * 15)::integer);
      exit when v_closed > now();

      -- Smjena se upisuje odmah zaključena, pa ne šalje obavještenje na Telegram.
      insert into public.shifts
        (id, venue_id, worker_id, worker_name, business_date, seq, opened_at, closed_at, updated_at)
      values
        (v_shift, v_venue.id, v_workers[v_w], v_names[v_w], v_date, v_slot, v_opened, v_closed, v_closed);
      v_receipt := null;
      v_sank := 0;

      for v_item in select * from demo_items order by sort_order, name loop
        v_open := v_item.stock;
        v_received := 0;
        -- Roba stiže ujutro, kad zaliha padne ispod tri smjene prodaje; kafa u kilogramima.
        if v_slot = 1 and v_item.kind = 'stock' and v_open < greatest(6, v_item.rate * 3) then
          v_received := greatest(12, ceil(v_item.rate * 9.0 / 6) * 6)::integer;
        elsif v_slot = 1 and v_item.kind = 'counter' and v_open < v_item.rate * 3 * v_item.portion then
          v_received := (ceil(v_item.rate * 9.0 * v_item.portion / 1000) * 1000)::integer;
        end if;
        if v_received > 0 then
          if v_receipt is null then
            v_receipt := gen_random_uuid();
            insert into public.receipts (id, shift_id, venue_id, created_at, closed_at)
            values (v_receipt, v_shift, v_venue.id, v_opened + interval '40 minutes',
              v_opened + interval '45 minutes');
          end if;
          insert into public.receipt_lines (receipt_id, item_id, venue_id, qty)
          values (v_receipt, v_item.id, v_venue.id, v_received);
        end if;
        v_used := round(
          v_item.rate * v_busy
          * case when v_item.evening then (case v_slot when 1 then 0.5 else 1.5 end)
                 when v_item.kind = 'counter' then (case v_slot when 1 then 1.3 else 0.7 end)
                 else 1 end
          * (0.55 + random() * 0.9)
        )::integer;
        if v_item.kind = 'stock' then
          -- Kod trećeg konobara ponekad "nestane" mnogo više nego inače.
          if v_w = 3 and random() < 0.004 then
            v_used := v_used * 3 + 4;
          end if;
          v_used := least(v_used, v_open + v_received);
          v_closing := v_open + v_received - v_used;
          -- Drugi konobar ponekad prebroji više nego što je moglo biti.
          if v_w = 2 and random() < 0.006 then
            v_used := -(1 + floor(random() * 2)::integer);
            v_closing := v_open + v_received - v_used;
          end if;
        else
          -- Prodane porcije skidaju svoju gramažu sa zalihe.
          v_used := least(v_used, (v_open + v_received) / v_item.portion);
          v_closing := v_open + v_received - v_used * v_item.portion;
        end if;
        insert into public.shift_lines
          (shift_id, item_id, venue_id, item_name, kind, price, sort_order, opening_qty, closing_qty)
        values
          (v_shift, v_item.id, v_venue.id, v_item.name, v_item.kind, v_item.price, v_item.sort_order,
           v_open, v_closing);
        v_sank := v_sank + v_used * v_item.price;
        update demo_items set stock = v_closing where id = v_item.id;
      end loop;

      -- Rashod iz kase
      for e in 1..floor(random() * 2.4)::integer loop
        insert into public.expenses (id, shift_id, venue_id, description, amount, created_at)
        values (gen_random_uuid(), v_shift, v_venue.id,
          v_spends[1 + floor(random() * array_length(v_spends, 1))::integer],
          (300 + floor(random() * 12) * 50)::integer,
          v_opened + make_interval(mins => 30 + floor(random() * 400)::integer));
      end loop;
      select coalesce(sum(x.amount), 0) into v_spent from public.expenses x where x.shift_id = v_shift;

      -- Kuhinja i predaja: treći konobar često fali, prvi ponekad ima sitan višak.
      v_kitchen := case when random() < 0.65
        then (round(v_busy * (2000 + random() * 9000) / 50) * 50)::integer else 0 end;
      v_total := v_sank + v_kitchen - v_spent;
      v_diff := case
        when v_w = 3 and random() < 0.35 then -(500 + floor(random() * 6) * 250)::integer
        when v_w = 1 and random() < 0.12 then (100 + floor(random() * 4) * 100)::integer
        when random() < 0.04 then -(200 + floor(random() * 3) * 100)::integer
        else 0 end;
      v_card := (round(v_total * (0.1 + random() * 0.2) / 50) * 50)::integer;
      update public.shifts s
      set kitchen = v_kitchen,
          card = v_card,
          cash = greatest(0, v_total + v_diff - v_card)
      where s.id = v_shift;
    end loop;
  end loop;

  raise notice 'Lokal %: % probnih smjena od %, konobari: %.',
    v_venue.name,
    (select count(*) from public.shifts s where s.venue_id = v_venue.id and s.id::text like 'de3d0000-%'),
    v_from, array_to_string(v_names, ', ');
end;
$$;
