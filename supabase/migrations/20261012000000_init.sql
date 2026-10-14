-- Šanko: šema za više kafića u jednoj bazi.
-- Firma (organizations) -> lokali (venues) -> radnici, artikli, smjene.
-- Gazda se prijavljuje e-mailom i vidi samo lokale svoje firme.
-- Konobar se na svom telefonu prijavljuje kodom lokala i PIN-om; vidi samo svoj lokal i svoje smjene.
-- Naloge kafićima otvara prodavac kroz vendor.create_customer (SQL Editor), ne aplikacija.

create schema if not exists private;
create schema if not exists vendor;
create extension if not exists pgcrypto with schema extensions;

create type public.item_kind as enum ('stock', 'counter');

-- ---------------------------------------------------------------------------
-- Tabele
-- ---------------------------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

create table public.org_admins (
  org_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  primary key (org_id, user_id)
);
create index org_admins_user_id_idx on public.org_admins (user_id);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  -- Kod koji konobar jednom ukuca na telefonu da ga veže za lokal.
  code text not null unique,
  timezone text not null default 'Europe/Sarajevo',
  -- Zadnji plaćeni dan. Nakon njega nema prijave ni novih smjena; stari podaci ostaju vidljivi.
  paid_until date not null,
  created_at timestamptz not null default now()
);
create index venues_org_id_idx on public.venues (org_id);

create table public.workers (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  -- Obrisan radnik se samo isključuje, da stare smjene zadrže ime.
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index workers_venue_id_idx on public.workers (venue_id);

-- PIN se čuva samo kao hash i nikad ne izlazi iz baze.
create table private.worker_secrets (
  worker_id uuid primary key references public.workers (id) on delete cascade,
  pin_hash text not null
);

-- Koji telefon (anonimni korisnik) je prijavljen kao koji radnik.
create table private.worker_sessions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  worker_id uuid not null references public.workers (id) on delete cascade,
  venue_id uuid not null references public.venues (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index worker_sessions_worker_id_idx on private.worker_sessions (worker_id);

create table private.login_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  venue_code text not null,
  at timestamptz not null default now()
);
create index login_attempts_user_idx on private.login_attempts (user_id, at);
create index login_attempts_code_idx on private.login_attempts (venue_code, at);

-- Zaliha se broji na komad; brojač je stanje s aparata koje samo raste. Cijena je u feninzima.
create table public.items (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  kind public.item_kind not null default 'stock',
  price integer not null check (price >= 0),
  initial_qty integer not null default 0 check (initial_qty >= 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index items_venue_id_idx on public.items (venue_id);

create table public.shifts (
  id uuid primary key,
  venue_id uuid not null references public.venues (id) on delete cascade,
  worker_id uuid not null references public.workers (id),
  worker_name text not null,
  business_date date not null,
  seq integer not null,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  updated_at timestamptz not null default now()
);
create unique index shifts_one_open_per_venue on public.shifts (venue_id) where closed_at is null;
create index shifts_venue_date_idx on public.shifts (venue_id, business_date);
create index shifts_worker_id_idx on public.shifts (worker_id);

-- Naziv, vrsta i cijena se kopiraju pri otvaranju smjene,
-- da kasnija promjena cjenovnika ne mijenja stare obračune.
create table public.shift_lines (
  shift_id uuid not null references public.shifts (id) on delete cascade,
  item_id uuid not null references public.items (id),
  venue_id uuid not null,
  item_name text not null,
  kind public.item_kind not null,
  price integer not null,
  sort_order integer not null,
  opening_qty integer not null,
  closing_qty integer check (closing_qty >= 0),
  primary key (shift_id, item_id)
);

-- Jedan ulaz je jedna dostava. closed_at NULL znači da je još u unosu i ne ulazi u obračun.
create table public.receipts (
  id uuid primary key,
  shift_id uuid not null references public.shifts (id) on delete cascade,
  venue_id uuid not null,
  created_at timestamptz not null,
  closed_at timestamptz
);
create index receipts_shift_id_idx on public.receipts (shift_id);

create table public.receipt_lines (
  receipt_id uuid not null references public.receipts (id) on delete cascade,
  item_id uuid not null references public.items (id),
  venue_id uuid not null,
  qty integer not null check (qty <> 0),
  primary key (receipt_id, item_id)
);

create table public.expenses (
  id uuid primary key,
  shift_id uuid not null references public.shifts (id) on delete cascade,
  venue_id uuid not null,
  description text not null check (length(trim(description)) > 0),
  amount integer not null check (amount > 0),
  created_at timestamptz not null
);
create index expenses_shift_id_idx on public.expenses (shift_id);

-- ---------------------------------------------------------------------------
-- Pomoćne funkcije za pravila pristupa
-- ---------------------------------------------------------------------------

create function private.is_venue_admin(p_venue_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.venues v
    join public.org_admins a on a.org_id = v.org_id
    where v.id = p_venue_id and a.user_id = (select auth.uid())
  );
$$;

create function private.is_org_admin(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.org_admins a
    where a.org_id = p_org_id and a.user_id = (select auth.uid())
  );
$$;

-- Lokal i radnik za koje je ovaj telefon prijavljen; null ako nije.
create function private.session_venue()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.venue_id from private.worker_sessions s where s.user_id = (select auth.uid());
$$;

create function private.session_worker()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.worker_id from private.worker_sessions s where s.user_id = (select auth.uid());
$$;

create function private.venue_is_paid(p_venue public.venues)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_venue.paid_until >= (now() at time zone p_venue.timezone)::date;
$$;

-- ---------------------------------------------------------------------------
-- Okidači
-- ---------------------------------------------------------------------------

create function private.items_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sort_order = 0 then
    select coalesce(max(i.sort_order), 0) + 1 into new.sort_order
    from public.items i
    where i.venue_id = new.venue_id;
  end if;
  return new;
end;
$$;

create trigger items_before_insert
  before insert on public.items
  for each row execute function private.items_before_insert();

-- Artikal dodan usred smjene ulazi odmah u nju, da ga konobar može primiti i prebrojati.
create function private.items_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.shift_lines
    (shift_id, item_id, venue_id, item_name, kind, price, sort_order, opening_qty)
  select s.id, new.id, new.venue_id, new.name, new.kind, new.price, new.sort_order, new.initial_qty
  from public.shifts s
  where s.venue_id = new.venue_id and s.closed_at is null;
  return null;
end;
$$;

create trigger items_after_insert
  after insert on public.items
  for each row execute function private.items_after_insert();

-- ---------------------------------------------------------------------------
-- Funkcije za telefon (konobar)
-- ---------------------------------------------------------------------------

-- Prijava konobara. Telefon je prije toga anonimno prijavljen u Supabase Auth.
-- Vraća {ok: true, worker, venue} ili {ok: false, error}. Greška se vraća, a ne baca,
-- da bi pogrešan pokušaj ostao zapisan.
create function public.waiter_login(p_venue_code text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(trim(p_venue_code));
  v_venue public.venues;
  v_worker public.workers;
begin
  if v_uid is null then
    raise exception 'Uređaj nije prijavljen' using errcode = '42501';
  end if;

  if (select count(*) from private.login_attempts a
      where a.user_id = v_uid and a.at > now() - interval '15 minutes') >= 5
    or (select count(*) from private.login_attempts a
        where a.venue_code = v_code and a.at > now() - interval '15 minutes') >= 30
  then
    return jsonb_build_object(
      'ok', false,
      'error', 'Previše pogrešnih pokušaja. Pokušajte ponovo za 15 minuta.'
    );
  end if;

  select * into v_venue from public.venues v where v.code = v_code;
  if found then
    select w.* into v_worker
    from public.workers w
    join private.worker_secrets s on s.worker_id = w.id
    where w.venue_id = v_venue.id
      and w.active
      and s.pin_hash = extensions.crypt(p_pin, s.pin_hash);
  end if;

  if v_worker.id is null then
    insert into private.login_attempts (user_id, venue_code) values (v_uid, v_code);
    return jsonb_build_object('ok', false, 'error', 'Pogrešan kod lokala ili PIN.');
  end if;

  if not private.venue_is_paid(v_venue) then
    return jsonb_build_object('ok', false, 'error', 'Pretplata za ovaj lokal je istekla.');
  end if;

  delete from private.login_attempts a where a.user_id = v_uid;
  insert into private.worker_sessions (user_id, worker_id, venue_id)
  values (v_uid, v_worker.id, v_venue.id)
  on conflict (user_id) do update
    set worker_id = excluded.worker_id, venue_id = excluded.venue_id, created_at = now();

  return jsonb_build_object(
    'ok', true,
    'worker', jsonb_build_object('id', v_worker.id, 'name', v_worker.name),
    'venue', jsonb_build_object('id', v_venue.id, 'name', v_venue.name)
  );
end;
$$;

-- Otvara smjenu za prijavljenog radnika i vraća njen id. Traži internet, jer server
-- garantuje da je u lokalu otvorena samo jedna smjena i daje početno stanje iz prethodne.
-- Ako radnik već ima otvorenu smjenu (npr. na novom telefonu), vraća nju.
create function public.start_shift(p_shift_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.worker_sessions;
  v_venue public.venues;
  v_worker public.workers;
  v_open public.shifts;
  v_date date;
begin
  select * into v_session from private.worker_sessions s where s.user_id = auth.uid();
  if not found then
    raise exception 'Niste prijavljeni' using errcode = '42501';
  end if;

  -- Zaključavanje reda lokala reda istovremene pokušaje otvaranja smjene.
  select * into v_venue from public.venues v where v.id = v_session.venue_id for update;
  select * into v_worker from public.workers w where w.id = v_session.worker_id;

  select * into v_open from public.shifts s where s.venue_id = v_venue.id and s.closed_at is null;
  if found then
    if v_open.worker_id = v_worker.id then
      return v_open.id;
    end if;
    raise exception 'Smjenu još nije zaključio/la %.', v_open.worker_name using errcode = 'P0001';
  end if;

  if not private.venue_is_paid(v_venue) then
    raise exception 'Pretplata za ovaj lokal je istekla.' using errcode = 'P0001';
  end if;

  v_date := (now() at time zone v_venue.timezone)::date;
  insert into public.shifts (id, venue_id, worker_id, worker_name, business_date, seq)
  values (
    p_shift_id, v_venue.id, v_worker.id, v_worker.name, v_date,
    (select coalesce(max(s.seq), 0) + 1 from public.shifts s
     where s.venue_id = v_venue.id and s.business_date = v_date)
  );

  -- Početno stanje je krajnje stanje iz zadnje zaključene smjene u kojoj je artikal bio.
  insert into public.shift_lines
    (shift_id, item_id, venue_id, item_name, kind, price, sort_order, opening_qty)
  select
    p_shift_id, i.id, i.venue_id, i.name, i.kind, i.price, i.sort_order,
    coalesce(
      (select l.closing_qty
       from public.shift_lines l
       join public.shifts s on s.id = l.shift_id
       where l.item_id = i.id and s.closed_at is not null
       order by s.opened_at desc
       limit 1),
      i.initial_qty)
  from public.items i
  where i.venue_id = v_venue.id and i.active;

  return p_shift_id;
end;
$$;

-- Telefon šalje cijelo stanje svoje smjene; poziv se može ponavljati bez štete.
-- p_shift: {id, closed_at, counts: [{item_id, closing_qty}],
--           receipts: [{id, created_at, closed_at, lines: [{item_id, qty}]}],
--           expenses: [{id, description, amount, created_at}]}
-- Kad je closed_at zadan, smjena se zaključuje i više se ne može mijenjati.
create function public.sync_shift(p_shift jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := (p_shift ->> 'id')::uuid;
  v_closed_at timestamptz := (p_shift ->> 'closed_at')::timestamptz;
  v_receipts jsonb := coalesce(p_shift -> 'receipts', '[]'::jsonb);
  v_shift public.shifts;
begin
  select * into v_shift from public.shifts s where s.id = v_id for update;
  if not found or v_shift.worker_id is distinct from private.session_worker() then
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
      updated_at = now()
  where s.id = v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Funkcije za admin panel (gazda)
-- ---------------------------------------------------------------------------

-- Dodaje radnika ili mijenja postojećeg. PIN je obavezan za novog radnika;
-- kod izmjene null znači da PIN ostaje isti. PIN je jedinstven unutar lokala.
create function public.admin_save_worker(
  p_venue_id uuid,
  p_name text,
  p_pin text default null,
  p_worker_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := p_worker_id;
begin
  if not private.is_venue_admin(p_venue_id) then
    raise exception 'Nemate pristup ovom lokalu' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_name, ''))) = 0 then
    raise exception 'Unesite ime radnika.' using errcode = 'P0001';
  end if;
  if p_pin is null and v_id is null then
    raise exception 'Unesite PIN.' using errcode = 'P0001';
  end if;
  if p_pin is not null then
    if p_pin !~ '^\d{4}$' then
      raise exception 'PIN mora imati tačno 4 cifre.' using errcode = 'P0001';
    end if;
    if exists (
      select 1
      from public.workers w
      join private.worker_secrets s on s.worker_id = w.id
      where w.venue_id = p_venue_id
        and w.active
        and w.id is distinct from v_id
        and s.pin_hash = extensions.crypt(p_pin, s.pin_hash)
    ) then
      raise exception 'Taj PIN već koristi drugi radnik.' using errcode = 'P0001';
    end if;
  end if;

  if v_id is null then
    insert into public.workers (venue_id, name) values (p_venue_id, trim(p_name))
    returning id into v_id;
  else
    update public.workers w set name = trim(p_name)
    where w.id = v_id and w.venue_id = p_venue_id and w.active;
    if not found then
      raise exception 'Radnik ne postoji.' using errcode = 'P0002';
    end if;
  end if;

  if p_pin is not null then
    insert into private.worker_secrets (worker_id, pin_hash)
    values (v_id, extensions.crypt(p_pin, extensions.gen_salt('bf')))
    on conflict (worker_id) do update set pin_hash = excluded.pin_hash;
    -- Novi PIN odjavljuje radnika sa svih telefona.
    delete from private.worker_sessions s where s.worker_id = v_id;
  end if;

  return v_id;
end;
$$;

-- Briše radnika: odmah ga odjavljuje sa svih telefona i oslobađa njegov PIN.
create function public.admin_remove_worker(p_worker_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_worker public.workers;
begin
  select * into v_worker from public.workers w where w.id = p_worker_id;
  if not found or not private.is_venue_admin(v_worker.venue_id) then
    raise exception 'Radnik ne postoji ili nemate pristup' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.shifts s where s.worker_id = p_worker_id and s.closed_at is null
  ) then
    raise exception 'Radnik ima otvorenu smjenu. Prvo je treba zaključiti.' using errcode = 'P0001';
  end if;
  update public.workers w set active = false where w.id = p_worker_id;
  delete from private.worker_sessions s where s.worker_id = p_worker_id;
  delete from private.worker_secrets s where s.worker_id = p_worker_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Funkcije za prodavca (pokreću se iz SQL Editora, aplikacija ih ne može pozvati)
-- ---------------------------------------------------------------------------

create function vendor.new_venue_code()
returns text
language plpgsql
set search_path = ''
as $$
declare
  -- Bez znakova koji se lako zamijene (0/O, 1/I/L).
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    select string_agg(substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::integer, 1), '')
    into v_code
    from generate_series(1, 6);
    exit when not exists (select 1 from public.venues v where v.code = v_code);
  end loop;
  return v_code;
end;
$$;

-- Dodaje lokal postojećoj firmi i vraća njegov kod.
create function vendor.add_venue(p_org_id uuid, p_venue_name text, p_paid_until date)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_code text := vendor.new_venue_code();
begin
  insert into public.venues (org_id, name, code, paid_until)
  values (p_org_id, p_venue_name, v_code, p_paid_until);
  return v_code;
end;
$$;

-- Otvara novog kupca: firmu, prvi lokal i gazdu. Nalog gazde mora već postojati
-- (Authentication -> Users -> Add user). Vraća kod lokala za telefone konobara.
create function vendor.create_customer(
  p_org_name text,
  p_venue_name text,
  p_owner_email text,
  p_paid_until date
)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_org_id uuid;
begin
  select u.id into v_user_id from auth.users u where lower(u.email) = lower(trim(p_owner_email));
  if v_user_id is null then
    raise exception 'Korisnik % ne postoji. Prvo ga dodajte u Authentication -> Users.', p_owner_email;
  end if;
  insert into public.organizations (name) values (p_org_name) returning id into v_org_id;
  insert into public.org_admins (org_id, user_id) values (v_org_id, v_user_id);
  return vendor.add_venue(v_org_id, p_venue_name, p_paid_until);
end;
$$;

-- ---------------------------------------------------------------------------
-- Pravila pristupa (RLS). Upis u smjene, ulaze, rashode i radnike ide samo kroz funkcije.
-- ---------------------------------------------------------------------------

alter table public.organizations enable row level security;
alter table public.org_admins enable row level security;
alter table public.venues enable row level security;
alter table public.workers enable row level security;
alter table public.items enable row level security;
alter table public.shifts enable row level security;
alter table public.shift_lines enable row level security;
alter table public.receipts enable row level security;
alter table public.receipt_lines enable row level security;
alter table public.expenses enable row level security;

create policy organizations_select on public.organizations
  for select to authenticated using (private.is_org_admin(id));

create policy org_admins_select on public.org_admins
  for select to authenticated using (user_id = (select auth.uid()));

create policy venues_select on public.venues
  for select to authenticated
  using (private.is_org_admin(org_id) or id = (select private.session_venue()));

-- Gazda vidi sve radnike lokala, konobar samo sebe.
create policy workers_select on public.workers
  for select to authenticated
  using (private.is_venue_admin(venue_id) or id = (select private.session_worker()));

create policy items_select on public.items
  for select to authenticated
  using (private.is_venue_admin(venue_id) or venue_id = (select private.session_venue()));
create policy items_insert on public.items
  for insert to authenticated with check (private.is_venue_admin(venue_id));
create policy items_update on public.items
  for update to authenticated
  using (private.is_venue_admin(venue_id)) with check (private.is_venue_admin(venue_id));

-- Gazda vidi sve smjene lokala, konobar samo svoje.
create policy shifts_select on public.shifts
  for select to authenticated
  using (private.is_venue_admin(venue_id) or worker_id = (select private.session_worker()));

create policy shift_lines_select on public.shift_lines
  for select to authenticated
  using (
    private.is_venue_admin(venue_id)
    or exists (
      select 1 from public.shifts s
      where s.id = shift_id and s.worker_id = (select private.session_worker())
    )
  );

create policy receipts_select on public.receipts
  for select to authenticated
  using (
    private.is_venue_admin(venue_id)
    or exists (
      select 1 from public.shifts s
      where s.id = shift_id and s.worker_id = (select private.session_worker())
    )
  );

create policy receipt_lines_select on public.receipt_lines
  for select to authenticated
  using (
    private.is_venue_admin(venue_id)
    or exists (
      select 1 from public.receipts r
      join public.shifts s on s.id = r.shift_id
      where r.id = receipt_id and s.worker_id = (select private.session_worker())
    )
  );

create policy expenses_select on public.expenses
  for select to authenticated
  using (
    private.is_venue_admin(venue_id)
    or exists (
      select 1 from public.shifts s
      where s.id = shift_id and s.worker_id = (select private.session_worker())
    )
  );

-- ---------------------------------------------------------------------------
-- Dozvole
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant insert on public.items to authenticated;
-- Vrsta i lokal artikla se ne mijenjaju naknadno.
grant update (name, price, initial_qty, sort_order, active) on public.items to authenticated;

grant usage on schema private to authenticated;
revoke execute on all functions in schema private from public;
grant execute on function
  private.is_venue_admin(uuid),
  private.is_org_admin(uuid),
  private.session_venue(),
  private.session_worker()
to authenticated;

revoke execute on all functions in schema vendor from public;

revoke execute on function public.waiter_login(text, text) from public, anon;
revoke execute on function public.start_shift(uuid) from public, anon;
revoke execute on function public.sync_shift(jsonb) from public, anon;
revoke execute on function public.admin_save_worker(uuid, text, text, uuid) from public, anon;
revoke execute on function public.admin_remove_worker(uuid) from public, anon;
grant execute on function public.waiter_login(text, text) to authenticated;
grant execute on function public.start_shift(uuid) to authenticated;
grant execute on function public.sync_shift(jsonb) to authenticated;
grant execute on function public.admin_save_worker(uuid, text, text, uuid) to authenticated;
grant execute on function public.admin_remove_worker(uuid) to authenticated;

-- Admin panel se osvježava uživo kad telefon pošalje smjenu.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.shifts;
  end if;
end;
$$;
