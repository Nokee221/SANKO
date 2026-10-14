-- Panel za prodavca: pregled kafića i pretplata, produženja sa zapisom uplate i otvaranje
-- novih kafića. Sve funkcije provjeravaju da je pozivalac prodavac (private.vendor_admins).
-- Prodavca (superadmina) postavlja skripta supabase/postavi_superadmina.sql.

create table private.vendor_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

-- Jedan red sa podešavanjima prodavca.
create table private.vendor_settings (
  id boolean primary key default true check (id),
  -- Mjesečna cijena po lokalu, u feninzima.
  monthly_price integer not null default 0 check (monthly_price >= 0)
);
insert into private.vendor_settings default values;

create table private.payments (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.venues (id) on delete cascade,
  amount integer not null check (amount >= 0),
  months integer not null default 0 check (months >= 0),
  paid_until_before date not null,
  paid_until_after date not null,
  note text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index payments_venue_id_idx on private.payments (venue_id);

create function private.require_vendor()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from private.vendor_admins v where v.user_id = auth.uid()) then
    raise exception 'Samo za prodavca' using errcode = '42501';
  end if;
end;
$$;

-- Da li je prijavljeni korisnik prodavac; aplikacija prema tome bira panel.
create function public.vendor_whoami()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.vendor_admins v where v.user_id = auth.uid());
$$;

-- Svi lokali sa vlasnicima, pretplatom i time koliko se aplikacija koristi.
create function public.vendor_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_vendor();
  return jsonb_build_object(
    'monthly_price', (select s.monthly_price from private.vendor_settings s),
    'venues', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', v.id,
          'org_id', o.id,
          'org_name', o.name,
          'name', v.name,
          'code', v.code,
          'paid_until', v.paid_until,
          'created_at', v.created_at,
          'owner_emails', coalesce((
            select jsonb_agg(u.email order by u.email)
            from public.org_admins a join auth.users u on u.id = a.user_id
            where a.org_id = o.id), '[]'::jsonb),
          'workers', (select count(*) from public.workers w where w.venue_id = v.id and w.active),
          'last_shift_at', (select max(s.opened_at) from public.shifts s where s.venue_id = v.id),
          'shifts_30d', (
            select count(*) from public.shifts s
            where s.venue_id = v.id and s.opened_at > now() - interval '30 days')
        )
        order by v.paid_until, o.name, v.name)
      from public.venues v
      join public.organizations o on o.id = v.org_id
    ), '[]'::jsonb)
  );
end;
$$;

-- Produženje za cijele mjesece, od isteka ili od danas ako je već istekla; uplata se zapisuje.
create function public.vendor_extend(p_venue_id uuid, p_months integer, p_amount integer, p_note text default null)
returns date
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue public.venues;
  v_new date;
begin
  perform private.require_vendor();
  if p_months < 1 or p_months > 36 then
    raise exception 'Broj mjeseci mora biti od 1 do 36.' using errcode = '22023';
  end if;
  select * into v_venue from public.venues v where v.id = p_venue_id for update;
  if not found then
    raise exception 'Lokal ne postoji' using errcode = 'P0002';
  end if;
  v_new := (greatest(v_venue.paid_until, current_date) + make_interval(months => p_months))::date;
  update public.venues v set paid_until = v_new where v.id = p_venue_id;
  insert into private.payments
    (venue_id, amount, months, paid_until_before, paid_until_after, note, created_by)
  values
    (p_venue_id, coalesce(p_amount, 0), p_months, v_venue.paid_until, v_new,
     nullif(trim(coalesce(p_note, '')), ''), auth.uid());
  return v_new;
end;
$$;

-- Ručno postavljanje datuma, npr. ispravka ili zaključavanje (jučerašnji datum).
create function public.vendor_set_paid_until(p_venue_id uuid, p_date date, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_venue public.venues;
begin
  perform private.require_vendor();
  select * into v_venue from public.venues v where v.id = p_venue_id for update;
  if not found then
    raise exception 'Lokal ne postoji' using errcode = 'P0002';
  end if;
  update public.venues v set paid_until = p_date where v.id = p_venue_id;
  insert into private.payments
    (venue_id, amount, months, paid_until_before, paid_until_after, note, created_by)
  values
    (p_venue_id, 0, 0, v_venue.paid_until, p_date,
     coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Ručna izmjena datuma'), auth.uid());
end;
$$;

-- Novi lokal postojeće firme; vraća kod za telefone.
create function public.vendor_add_venue(p_org_id uuid, p_venue_name text, p_paid_until date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_vendor();
  if not exists (select 1 from public.organizations o where o.id = p_org_id) then
    raise exception 'Firma ne postoji' using errcode = 'P0002';
  end if;
  return vendor.add_venue(p_org_id, trim(p_venue_name), p_paid_until);
end;
$$;

-- Novi kupac za gazdu čiji je nalog upravo napravila serverska funkcija create-owner.
-- Vraća kod lokala. Prva uplata (ako je iznos veći od nule) se zapisuje.
create function public.vendor_create_customer(
  p_org_name text,
  p_venue_name text,
  p_owner_id uuid,
  p_paid_until date,
  p_amount integer default 0,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_code text;
begin
  perform private.require_vendor();
  if length(trim(coalesce(p_org_name, ''))) = 0 or length(trim(coalesce(p_venue_name, ''))) = 0 then
    raise exception 'Unesite naziv firme i lokala.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_owner_id) then
    raise exception 'Nalog gazde ne postoji' using errcode = 'P0002';
  end if;
  insert into public.organizations (name) values (trim(p_org_name)) returning id into v_org;
  insert into public.org_admins (org_id, user_id) values (v_org, p_owner_id);
  v_code := vendor.add_venue(v_org, trim(p_venue_name), p_paid_until);
  insert into private.payments
    (venue_id, amount, months, paid_until_before, paid_until_after, note, created_by)
  select v.id, coalesce(p_amount, 0), 0, current_date, p_paid_until,
    coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Novi kupac'), auth.uid()
  from public.venues v where v.code = v_code;
  return v_code;
end;
$$;

-- Sve uplate, najnovije prve.
create function public.vendor_payments()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_vendor();
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'venue_id', p.venue_id,
        'venue_name', v.name,
        'org_name', o.name,
        'amount', p.amount,
        'months', p.months,
        'paid_until_before', p.paid_until_before,
        'paid_until_after', p.paid_until_after,
        'note', p.note,
        'created_at', p.created_at
      )
      order by p.created_at desc)
    from private.payments p
    join public.venues v on v.id = p.venue_id
    join public.organizations o on o.id = v.org_id
  ), '[]'::jsonb);
end;
$$;

create function public.vendor_set_price(p_price integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_vendor();
  if p_price < 0 then
    raise exception 'Cijena ne može biti negativna.' using errcode = 'P0001';
  end if;
  update private.vendor_settings s set monthly_price = p_price where s.id;
end;
$$;

revoke execute on function private.require_vendor() from public;
revoke execute on function
  public.vendor_whoami(),
  public.vendor_overview(),
  public.vendor_extend(uuid, integer, integer, text),
  public.vendor_set_paid_until(uuid, date, text),
  public.vendor_add_venue(uuid, text, date),
  public.vendor_create_customer(text, text, uuid, date, integer, text),
  public.vendor_payments(),
  public.vendor_set_price(integer)
from public, anon;
grant execute on function
  public.vendor_whoami(),
  public.vendor_overview(),
  public.vendor_extend(uuid, integer, integer, text),
  public.vendor_set_paid_until(uuid, date, text),
  public.vendor_add_venue(uuid, text, date),
  public.vendor_create_customer(text, text, uuid, date, integer, text),
  public.vendor_payments(),
  public.vendor_set_price(integer)
to authenticated;

-- Superadmin se postavlja posebnom skriptom supabase/postavi_superadmina.sql,
-- na poseban nalog koji nije gazda nijednog kafića.
