-- Gazda može zaključiti smjenu iz admin panela kad je konobar ne može zaključiti sam
-- (otišao je, izgubio telefon). Bez ovoga bi lokal ostao blokiran, jer nova smjena
-- ne može početi dok je stara otvorena.

alter table public.shifts
  add column closed_by_admin boolean not null default false;

-- p_counts: [{"item_id": "...", "closing_qty": 12}] za artikle čije stanje gazda unosi ili
-- ispravlja; za ostale važi ono što je telefon već poslao. Stanje mora postojati za svaki artikal.
-- Ulaz koji konobar nije zaključio se odbacuje.
create function public.admin_close_shift(p_shift_id uuid, p_counts jsonb)
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
  if exists (
    select 1 from public.shift_lines sl
    where sl.shift_id = p_shift_id and sl.kind = 'counter' and sl.closing_qty < sl.opening_qty
  ) then
    raise exception 'Brojač ne može biti manji od prethodnog stanja.' using errcode = 'P0001';
  end if;

  delete from public.receipts r where r.shift_id = p_shift_id and r.closed_at is null;

  update public.shifts s
  set closed_at = now(), closed_by_admin = true, updated_at = now()
  where s.id = p_shift_id;
end;
$$;

revoke execute on function public.admin_close_shift(uuid, jsonb) from public, anon;
grant execute on function public.admin_close_shift(uuid, jsonb) to authenticated;
