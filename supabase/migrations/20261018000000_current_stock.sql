-- Trenutna zaliha za upozorenje na nisku zalihu: ostatak sa zadnjeg brojanja
-- (zaključene smjene), plus ulazi zaključeni u smjeni koja je još otvorena.
-- Brojači (kafa, Nes aparat) nisu zaliha i ne vraćaju se.

create function public.admin_current_stock(p_venue_id uuid)
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

  return coalesce((
    select jsonb_agg(
      jsonb_build_object('item_id', i.id, 'name', i.name, 'sort_order', i.sort_order, 'stock', st.stock)
      order by i.sort_order)
    from public.items i
    cross join lateral (
      select
        coalesce(
          (select l.closing_qty
           from public.shift_lines l
           join public.shifts s on s.id = l.shift_id
           where l.item_id = i.id and s.closed_at is not null
           order by s.opened_at desc
           limit 1),
          i.initial_qty)
        + coalesce(
          (select sum(rl.qty)
           from public.receipt_lines rl
           join public.receipts r on r.id = rl.receipt_id
           join public.shifts s on s.id = r.shift_id
           where rl.item_id = i.id and s.closed_at is null and r.closed_at is not null),
          0)::integer as stock
    ) st
    where i.venue_id = p_venue_id and i.active and i.kind = 'stock'
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.admin_current_stock(uuid) from public, anon;
grant execute on function public.admin_current_stock(uuid) to authenticated;
