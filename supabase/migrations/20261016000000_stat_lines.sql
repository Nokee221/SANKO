-- Podaci za prosječnu potrošnju i ulaz: utrošeno i primljeno po artiklu u svakoj
-- zaključenoj smjeni perioda. Vraća se kao jedan JSON niz, da granica broja redova
-- po upitu ne skrati dugačak period; prosjeke računa admin panel.

create function public.admin_stat_lines(p_venue_id uuid, p_from date, p_to date)
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
        'sort_order', l.sort_order,
        'business_date', s.business_date,
        'shift_id', s.id,
        'seq', s.seq,
        'worker_name', s.worker_name,
        'received', r.received,
        'consumed', case
          when l.kind = 'counter' then l.closing_qty - l.opening_qty
          else l.opening_qty + r.received - l.closing_qty
        end
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

revoke execute on function public.admin_stat_lines(uuid, date, date) from public, anon;
grant execute on function public.admin_stat_lines(uuid, date, date) to authenticated;
