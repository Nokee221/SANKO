-- Ispravka zaključene smjene: gazda može promijeniti ostatak (prebrojano stanje) i
-- primljenu količinu artikla. Svaka promjena se zapisuje, a ispravljen ostatak postaje
-- početno stanje tog artikla u sljedećoj smjeni.

create table public.shift_corrections (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.shifts (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  item_id uuid not null references public.items (id),
  item_name text not null,
  -- 'closing' je ostatak, 'received' je ukupno primljeno u smjeni.
  field text not null check (field in ('closing', 'received')),
  old_value integer not null,
  new_value integer not null,
  note text,
  corrected_by uuid references auth.users (id) on delete set null,
  corrected_at timestamptz not null default now()
);
create index shift_corrections_shift_id_idx on public.shift_corrections (shift_id);

-- Ispravka ulaza se upisuje kao poseban zaključen ulaz sa razlikom.
alter table public.receipts
  add column created_by_admin boolean not null default false;

alter table public.shift_corrections enable row level security;

create policy shift_corrections_select on public.shift_corrections
  for select to authenticated using (private.is_venue_admin(venue_id));

revoke all on public.shift_corrections from anon, authenticated;
grant select on public.shift_corrections to authenticated;

-- p_changes: [{"item_id": "...", "closing_qty": 80, "received": 24}]; oba polja nisu obavezna.
-- "received" je nova ukupna primljena količina u smjeni, a ne razlika.
create function public.admin_correct_shift(p_shift_id uuid, p_changes jsonb, p_note text default null)
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
      if v_line.kind = 'counter' then
        raise exception '% je brojač i nema ulaz.', v_line.item_name using errcode = 'P0001';
      end if;
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
      if v_line.kind = 'counter' and v_new < v_line.opening_qty then
        raise exception 'Brojač za % ne može biti manji od prethodnog stanja (%).',
          v_line.item_name, v_line.opening_qty using errcode = 'P0001';
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
          if v_line.kind = 'counter' and v_next_line.closing_qty < v_new then
            raise exception 'Brojač za % bi u sljedećoj smjeni bio manji od početnog stanja.',
              v_line.item_name using errcode = 'P0001';
          end if;
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

revoke execute on function public.admin_correct_shift(uuid, jsonb, text) from public, anon;
grant execute on function public.admin_correct_shift(uuid, jsonb, text) to authenticated;
