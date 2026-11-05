-- Na telefonu može ostati otvorena smjena drugog radnika koju je gazda u međuvremenu
-- zaključio s desktopa. Telefon tada pita server za stanje te smjene, da sljedeći radnik
-- ne ostane blokiran dok se prethodni ne prijavi na istom telefonu.

-- Vraća {id, closed_at} za smjenu iz lokala prijavljenog radnika, bez ikakvih unosa;
-- null kad takve smjene nema.
create function public.shift_status(p_token text, p_shift_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions := private.require_session(p_token);
begin
  return (
    select jsonb_build_object('id', s.id, 'closed_at', s.closed_at)
    from public.shifts s
    where s.id = p_shift_id and s.venue_id = v_session.venue_id
  );
end;
$$;

revoke execute on function public.shift_status(text, uuid) from public;
grant execute on function public.shift_status(text, uuid) to anon, authenticated;
