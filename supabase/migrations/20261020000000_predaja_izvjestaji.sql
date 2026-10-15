-- Predaja novca i kuhinja uz smjenu, minimalna zaliha artikala, izvještaji po smjenama
-- i obavještenje gazdi na Telegram kad se smjena zaključi.

-- ---------------------------------------------------------------------------
-- Predaja novca i kuhinja
-- ---------------------------------------------------------------------------

-- Konobar pri zaključenju unosi iznos kuhinje i koliko gotovine i kartica predaje.
-- Za predati je šank + kuhinja − rashod; razlika je predano − za predati (minus je manjak).
-- Smjene zaključene prije ove promjene nemaju predaju (null).
alter table public.shifts
  add column kitchen integer check (kitchen >= 0),
  add column cash integer check (cash >= 0),
  add column card integer check (card >= 0);

-- Telefon sada šalje i predaju: {kitchen, cash, card} uz ostatak smjene.
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

  if exists (
    select 1 from public.shift_lines sl
    where sl.shift_id = v_id and sl.kind = 'counter' and sl.closing_qty < sl.opening_qty
  ) then
    raise exception 'Brojač ne može biti manji od prethodnog stanja.' using errcode = 'P0001';
  end if;

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

-- Gazda koji zaključuje smjenu umjesto konobara može upisati i predaju:
-- p_handover {kitchen, cash, card}; bez nje smjena ostaje bez predaje.
drop function public.admin_close_shift(uuid, jsonb);

create function public.admin_close_shift(p_shift_id uuid, p_counts jsonb, p_handover jsonb default null)
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
  set closed_at = now(), closed_by_admin = true, updated_at = now(),
      kitchen = (p_handover ->> 'kitchen')::integer,
      cash = (p_handover ->> 'cash')::integer,
      card = (p_handover ->> 'card')::integer
  where s.id = p_shift_id;
end;
$$;

revoke execute on function public.admin_close_shift(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.admin_close_shift(uuid, jsonb, jsonb) to authenticated;

-- Ispravka predaje se zapisuje kao i ispravka artikla, samo bez artikla.
alter table public.shift_corrections
  alter column item_id drop not null,
  alter column old_value drop not null,
  drop constraint shift_corrections_field_check,
  add constraint shift_corrections_field_check
    check (field in ('closing', 'received', 'kitchen', 'cash', 'card'));

-- Gazda ispravlja kuhinju i predaju zaključene smjene; svaka promjena se zapisuje.
create function public.admin_set_handover(
  p_shift_id uuid,
  p_kitchen integer,
  p_cash integer,
  p_card integer,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shift public.shifts;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
  select * into v_shift from public.shifts s where s.id = p_shift_id for update;
  if not found or not private.is_venue_admin(v_shift.venue_id) then
    raise exception 'Smjena ne postoji ili nemate pristup' using errcode = '42501';
  end if;
  if v_shift.closed_at is null then
    raise exception 'Smjena još nije zaključena; predaju unosi konobar pri zaključenju.'
      using errcode = 'P0001';
  end if;
  if p_kitchen is null or p_cash is null or p_card is null
    or p_kitchen < 0 or p_cash < 0 or p_card < 0 then
    raise exception 'Unesite kuhinju, gotovinu i kartice (0 ako nema).' using errcode = 'P0001';
  end if;

  insert into public.shift_corrections
    (shift_id, venue_id, item_name, field, old_value, new_value, note, corrected_by)
  select p_shift_id, v_shift.venue_id, c.label, c.field, c.old_value, c.new_value, v_note, auth.uid()
  from (values
    ('Kuhinja', 'kitchen', v_shift.kitchen, p_kitchen),
    ('Gotovina', 'cash', v_shift.cash, p_cash),
    ('Kartice', 'card', v_shift.card, p_card)
  ) as c (label, field, old_value, new_value)
  where c.old_value is distinct from c.new_value;

  update public.shifts s
  set kitchen = p_kitchen, cash = p_cash, card = p_card, updated_at = now()
  where s.id = p_shift_id;
end;
$$;

revoke execute on function public.admin_set_handover(uuid, integer, integer, integer, text) from public, anon;
grant execute on function public.admin_set_handover(uuid, integer, integer, integer, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Zbir smjene: šank, kuhinja, rashod, predaja i anomalije
-- ---------------------------------------------------------------------------

-- Isti zbir koriste izvještaji i obavještenje, da brojevi budu svuda isti.
create function private.shift_summary(p_shift public.shifts)
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
      case when l.kind = 'counter' then l.opening_qty else l.opening_qty + r.received end as expected,
      case
        when l.kind = 'counter' then l.closing_qty - l.opening_qty
        else l.opening_qty + r.received - l.closing_qty
      end as consumed
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

revoke execute on function private.shift_summary(public.shifts) from public;

-- Zbirovi zaključenih smjena u periodu, za mjesečni pregled i izvještaj po konobaru.
create function public.admin_shift_summaries(p_venue_id uuid, p_from date, p_to date)
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
    select jsonb_agg(private.shift_summary(s) order by s.business_date, s.seq)
    from public.shifts s
    where s.venue_id = p_venue_id
      and s.closed_at is not null
      and s.business_date between p_from and p_to
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.admin_shift_summaries(uuid, date, date) from public, anon;
grant execute on function public.admin_shift_summaries(uuid, date, date) to authenticated;

-- Statistika sada nosi i cijenu, da mjesečni pregled zna promet po artiklu.
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

-- ---------------------------------------------------------------------------
-- Minimalna zaliha i narudžba
-- ---------------------------------------------------------------------------

-- Kad zaliha padne na minimum, artikal ide na listu za narudžbu, i to do količine
-- "naručiti do". Bez minimuma artikal se ne naručuje automatski.
alter table public.items
  add column min_qty integer check (min_qty >= 0),
  add column par_qty integer check (par_qty >= 0);

grant update (min_qty, par_qty) on public.items to authenticated;

-- ---------------------------------------------------------------------------
-- Obavještenja na Telegram
-- ---------------------------------------------------------------------------

-- Podešavanja servera koja upisuje serverska funkcija telegram-webhook pri podešavanju:
-- 'telegram_bot' (korisničko ime bota) i 'functions_url' (adresa serverskih funkcija).
create table private.app_settings (
  key text primary key,
  value text not null
);

-- Telegram razgovori koji primaju obavještenja za lokal.
create table private.telegram_chats (
  venue_id uuid not null references public.venues (id) on delete cascade,
  chat_id bigint not null,
  title text,
  linked_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (venue_id, chat_id)
);

-- Jednokratni kod iz linka t.me/<bot>?start=<kod>; važi 30 minuta.
create table private.telegram_link_codes (
  code text primary key,
  venue_id uuid not null references public.venues (id) on delete cascade,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

-- Smjene čije obavještenje tek treba poslati.
create table private.notify_outbox (
  shift_id uuid primary key references public.shifts (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  attempts integer not null default 0,
  sent_at timestamptz,
  last_error text
);

-- pg_net šalje HTTP zahtjev iz baze tek kad se transakcija potvrdi.
create extension if not exists pg_net with schema extensions;

-- Kad se smjena zaključi (konobar ili gazda), obavještenje ide u red i serverska funkcija
-- notify-shift se budi. Greška u slanju nikad ne smije spriječiti zaključenje smjene.
create function private.shifts_after_close()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
begin
  if not exists (select 1 from private.telegram_chats c where c.venue_id = new.venue_id) then
    return null;
  end if;
  insert into private.notify_outbox (shift_id, venue_id)
  values (new.id, new.venue_id)
  on conflict (shift_id) do nothing;

  select s.value into v_url from private.app_settings s where s.key = 'functions_url';
  if v_url is not null then
    begin
      perform net.http_post(
        url := v_url || '/notify-shift',
        body := jsonb_build_object('shift_id', new.id),
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    exception when others then
      -- Obavještenje ostaje u redu i šalje se sa sljedećim.
      null;
    end;
  end if;
  return null;
end;
$$;

create trigger shifts_after_close
  after update of closed_at on public.shifts
  for each row
  when (old.closed_at is null and new.closed_at is not null)
  execute function private.shifts_after_close();

-- Stanje veze sa Telegramom za admin panel.
create function public.admin_telegram_status(p_venue_id uuid)
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
  return jsonb_build_object(
    'bot', (select s.value from private.app_settings s where s.key = 'telegram_bot'),
    'chats', coalesce((
      select jsonb_agg(jsonb_build_object('title', c.title, 'created_at', c.created_at)
        order by c.created_at)
      from private.telegram_chats c where c.venue_id = p_venue_id), '[]'::jsonb)
  );
end;
$$;

-- Link koji gazda otvori na telefonu; pritiskom na Start u Telegramu razgovor se veže za lokal.
create function public.admin_telegram_link(p_venue_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bot text;
  v_code text := replace(gen_random_uuid()::text, '-', '');
begin
  if not private.is_venue_admin(p_venue_id) then
    raise exception 'Nemate pristup ovom lokalu' using errcode = '42501';
  end if;
  select s.value into v_bot from private.app_settings s where s.key = 'telegram_bot';
  if v_bot is null then
    raise exception 'Telegram obavještenja još nisu podešena na serveru. Javite se prodavcu.'
      using errcode = 'P0001';
  end if;
  delete from private.telegram_link_codes c where c.created_at < now() - interval '30 minutes';
  insert into private.telegram_link_codes (code, venue_id, created_by)
  values (v_code, p_venue_id, auth.uid());
  return 'https://t.me/' || v_bot || '?start=' || v_code;
end;
$$;

create function public.admin_telegram_unlink(p_venue_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_venue_admin(p_venue_id) then
    raise exception 'Nemate pristup ovom lokalu' using errcode = '42501';
  end if;
  delete from private.telegram_chats c where c.venue_id = p_venue_id;
end;
$$;

revoke execute on function
  public.admin_telegram_status(uuid),
  public.admin_telegram_link(uuid),
  public.admin_telegram_unlink(uuid)
from public, anon;
grant execute on function
  public.admin_telegram_status(uuid),
  public.admin_telegram_link(uuid),
  public.admin_telegram_unlink(uuid)
to authenticated;

-- Funkcije ispod poziva samo serverska funkcija, ključem servera (service_role).

-- Upisuje bota i adresu serverskih funkcija; poziva se pri podešavanju.
create function public.telegram_configure(p_bot text, p_functions_url text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.app_settings (key, value)
  values ('telegram_bot', p_bot), ('functions_url', p_functions_url)
  on conflict (key) do update set value = excluded.value;
$$;

-- Veže Telegram razgovor za lokal po kodu iz linka. Vraća naziv lokala, ili null
-- ako kod ne postoji ili je istekao.
create function public.telegram_claim_link(p_code text, p_chat_id bigint, p_title text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code private.telegram_link_codes;
begin
  delete from private.telegram_link_codes c
  where c.code = p_code and c.created_at > now() - interval '30 minutes'
  returning * into v_code;
  if not found then
    return null;
  end if;
  insert into private.telegram_chats (venue_id, chat_id, title, linked_by)
  values (v_code.venue_id, p_chat_id, p_title, v_code.created_by)
  on conflict (venue_id, chat_id) do update set title = excluded.title;
  return (select v.name from public.venues v where v.id = v_code.venue_id);
end;
$$;

-- Preuzima obavještenja za slanje: zbir smjene, naziv lokala i razgovore.
-- Preuzeto obavještenje drugi poziv ne dobija 2 minute, da ne ode dvaput.
create function public.notify_claim()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  with picked as (
    select o.shift_id from private.notify_outbox o
    where o.sent_at is null
      and o.attempts < 5
      and (o.claimed_at is null or o.claimed_at < now() - interval '2 minutes')
    order by o.created_at
    limit 20
    for update skip locked
  ), claimed as (
    update private.notify_outbox o
    set claimed_at = now(), attempts = o.attempts + 1
    from picked
    where o.shift_id = picked.shift_id
    returning o.shift_id
  )
  select array_agg(claimed.shift_id) into v_ids from claimed;

  return coalesce((
    select jsonb_agg(
      private.shift_summary(s) || jsonb_build_object(
        'venue_name', v.name,
        'chat_ids', (select coalesce(jsonb_agg(c.chat_id), '[]'::jsonb)
                     from private.telegram_chats c where c.venue_id = s.venue_id)))
    from public.shifts s
    join public.venues v on v.id = s.venue_id
    where s.id = any(v_ids)
  ), '[]'::jsonb);
end;
$$;

-- Zapisuje ishod slanja; sa greškom obavještenje ostaje u redu za sljedeći pokušaj.
create function public.notify_done(p_shift_id uuid, p_error text default null)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.notify_outbox o
  set sent_at = case when p_error is null then now() end,
      claimed_at = case when p_error is null then o.claimed_at end,
      last_error = p_error
  where o.shift_id = p_shift_id;
$$;

-- Razgovor koji je blokirao bota više ne prima obavještenja.
create function public.telegram_forget_chat(p_chat_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.telegram_chats c where c.chat_id = p_chat_id;
$$;

revoke execute on function
  public.telegram_configure(text, text),
  public.telegram_claim_link(text, bigint, text),
  public.notify_claim(),
  public.notify_done(uuid, text),
  public.telegram_forget_chat(bigint)
from public, anon, authenticated;
grant execute on function
  public.telegram_configure(text, text),
  public.telegram_claim_link(text, bigint, text),
  public.notify_claim(),
  public.notify_done(uuid, text),
  public.telegram_forget_chat(bigint)
to service_role;
