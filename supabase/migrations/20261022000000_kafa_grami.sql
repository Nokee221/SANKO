-- Kafa, nes i slično (vrsta "counter") se više ne vode kao brojač aparata, nego kao
-- zaliha u gramima. Konobar upisuje prodane porcije; iznos je porcije × cijena, a sa
-- zalihe se skida porcije × gramaža (npr. 50 kafa × 20 g = 1000 g od 145.000 g).
-- Utrošeno za sve artikle je (ostatak prije + primljeno − ostatak) / gramaža porcije,
-- a za artikle na komad je gramaža 1. Ulaz kafe se upisuje u gramima.
--
-- Postojeći artikli vrste "counter" dobijaju gramažu 1; gazda je postavlja u Artiklima.
-- Stare smjene vođene po brojaču aparata ovdje daju negativno utrošeno, pa ih je
-- najbolje obrisati (obrisi_sve_podatke.sql) ako su samo probne.

alter table public.items
  add column portion integer not null default 1 check (portion > 0);
alter table public.shift_lines
  add column portion integer not null default 1 check (portion > 0);

grant update (portion) on public.items to authenticated;

-- Gramaža se kopira u stavku smjene, kao naziv i cijena, da kasnija promjena
-- ne mijenja stare obračune. Pokriva i početak smjene i artikal dodan usred smjene.
create function private.shift_lines_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select i.portion into new.portion from public.items i where i.id = new.item_id;
  new.portion := coalesce(new.portion, 1);
  return new;
end;
$$;

create trigger shift_lines_before_insert
  before insert on public.shift_lines
  for each row execute function private.shift_lines_before_insert();

-- Telefon šalje ostatak u gramima; brojač više ne mora rasti.
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
      kitchen = (p_shift ->> 'kitchen')::integer,
      cash = (p_shift ->> 'cash')::integer,
      card = (p_shift ->> 'card')::integer,
      updated_at = now()
  where s.id = v_id;
end;
$$;

create or replace function public.admin_close_shift(p_shift_id uuid, p_counts jsonb, p_handover jsonb default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shift public.shifts;
begin
  select * into v_shift from public.shifts s where s.id = p_shift_id for update;
  if not found or not private.is_venue_admin(v_shift.venue_id) then
    raise exception 'Smjena ne postoji ili nemate pristup' using errcode = '42501';
  end if;
  if v_shift.closed_at is not null then
    return;
  end if;

  update public.shift_lines sl
  set closing_qty = c.closing_qty
  from jsonb_to_recordset(coalesce(p_counts, '[]'::jsonb)) as c (item_id uuid, closing_qty integer)
  where sl.shift_id = p_shift_id and sl.item_id = c.item_id;

  if exists (
    select 1 from public.shift_lines sl where sl.shift_id = p_shift_id and sl.closing_qty is null
  ) then
    raise exception 'Nije uneseno stanje za sve artikle.' using errcode = 'P0001';
  end if;

  delete from public.receipts r where r.shift_id = p_shift_id and r.closed_at is null;

  update public.shifts s
  set closed_at = now(), closed_by_admin = true, updated_at = now(),
      kitchen = (p_handover ->> 'kitchen')::integer,
      cash = (p_handover ->> 'cash')::integer,
      card = (p_handover ->> 'card')::integer
  where s.id = p_shift_id;
end;
$$;

-- Zbir smjene i statistika: utrošeno u porcijama za sve artikle.
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
    -- Prebrojano više nego što je moglo biti.
    'anomalies', coalesce(jsonb_agg(
      jsonb_build_object('item_name', t.item_name, 'expected', t.expected, 'counted', t.closing_qty)
      order by t.sort_order) filter (where t.consumed < 0), '[]'::jsonb)
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

create or replace function public.admin_stat_lines(p_venue_id uuid, p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_venue_admin(p_venue_id) then
    raise exception 'Nemate pristup ovom lokalu' using errcode = '42501';
  end if;
  if p_to - p_from > 400 then
    raise exception 'Period može biti najviše godinu dana.' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'item_id', l.item_id,
        'item_name', l.item_name,
        'kind', l.kind,
        'price', l.price,
        'sort_order', l.sort_order,
        'business_date', s.business_date,
        'shift_id', s.id,
        'seq', s.seq,
        'worker_name', s.worker_name,
        'received', r.received,
        'consumed', (l.opening_qty + r.received - l.closing_qty) / l.portion
      )
      order by s.business_date, s.seq, l.sort_order
    )
    from public.shifts s
    join public.shift_lines l on l.shift_id = s.id
    cross join lateral (
      select coalesce(sum(rl.qty), 0)::integer as received
      from public.receipt_lines rl
      join public.receipts rc on rc.id = rl.receipt_id
      where rc.shift_id = s.id and rc.closed_at is not null and rl.item_id = l.item_id
    ) r
    where s.venue_id = p_venue_id
      and s.closed_at is not null
      and s.business_date between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

-- Ispravka: i kafa sada ima ulaz (u gramima), a ostatak može ići gore i dolje.
create or replace function public.admin_correct_shift(p_shift_id uuid, p_changes jsonb, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shift public.shifts;
  v_change jsonb;
  v_line public.shift_lines;
  v_item uuid;
  v_received integer;
  v_new integer;
  v_receipt uuid;
  v_next public.shifts;
  v_next_line public.shift_lines;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  select * into v_shift from public.shifts s where s.id = p_shift_id for update;
  if not found or not private.is_venue_admin(v_shift.venue_id) then
    raise exception 'Smjena ne postoji ili nemate pristup' using errcode = '42501';
  end if;
  if v_shift.closed_at is null then
    raise exception 'Smjena još nije zaključena; ispravljaju se samo zaključene smjene.'
      using errcode = 'P0001';
  end if;

  for v_change in select * from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) loop
    v_item := (v_change ->> 'item_id')::uuid;
    select * into v_line from public.shift_lines l
    where l.shift_id = p_shift_id and l.item_id = v_item
    for update;
    if not found then
      raise exception 'Artikal nije u ovoj smjeni' using errcode = 'P0001';
    end if;

    -- Primljeno
    if v_change ? 'received' then
      v_new := (v_change ->> 'received')::integer;
      select coalesce(sum(rl.qty), 0)::integer into v_received
      from public.receipt_lines rl
      join public.receipts r on r.id = rl.receipt_id
      where r.shift_id = p_shift_id and r.closed_at is not null and rl.item_id = v_item;
      if v_new <> v_received then
        v_receipt := gen_random_uuid();
        insert into public.receipts (id, shift_id, venue_id, created_at, closed_at, created_by_admin)
        values (v_receipt, p_shift_id, v_shift.venue_id, now(), now(), true);
        insert into public.receipt_lines (receipt_id, item_id, venue_id, qty)
        values (v_receipt, v_item, v_shift.venue_id, v_new - v_received);
        insert into public.shift_corrections
          (shift_id, venue_id, item_id, item_name, field, old_value, new_value, note, corrected_by)
        values
          (p_shift_id, v_shift.venue_id, v_item, v_line.item_name, 'received', v_received, v_new,
           v_note, auth.uid());
      end if;
    end if;

    -- Ostatak
    if v_change ? 'closing_qty' then
      v_new := (v_change ->> 'closing_qty')::integer;
      if v_new < 0 then
        raise exception 'Ostatak ne može biti negativan.' using errcode = 'P0001';
      end if;
      if v_new is distinct from v_line.closing_qty then
        update public.shift_lines l set closing_qty = v_new
        where l.shift_id = p_shift_id and l.item_id = v_item;
        insert into public.shift_corrections
          (shift_id, venue_id, item_id, item_name, field, old_value, new_value, note, corrected_by)
        values
          (p_shift_id, v_shift.venue_id, v_item, v_line.item_name, 'closing', v_line.closing_qty,
           v_new, v_note, auth.uid());

        -- Sljedeća smjena u kojoj je artikal bio počinje od ispravljenog ostatka.
        select s.* into v_next
        from public.shifts s
        join public.shift_lines l on l.shift_id = s.id and l.item_id = v_item
        where s.venue_id = v_shift.venue_id and s.opened_at > v_shift.opened_at
        order by s.opened_at
        limit 1;
        if found then
          select * into v_next_line from public.shift_lines l
          where l.shift_id = v_next.id and l.item_id = v_item;
          update public.shift_lines l set opening_qty = v_new
          where l.shift_id = v_next.id and l.item_id = v_item;
          update public.shifts s set updated_at = now() where s.id = v_next.id;
        end if;
      end if;
    end if;
  end loop;

  update public.shifts s set updated_at = now() where s.id = p_shift_id;
end;
$$;
