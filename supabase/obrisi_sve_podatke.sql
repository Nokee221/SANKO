-- BRIŠE SVE PODATKE: sve kafiće, lokale, radnike, artikle, smjene, uplate i sve naloge
-- osim superadmina. Ostaju samo superadmin, katalog slika i cijena pretplate.
-- Ne može se poništiti. Pokreće se u Supabase SQL Editoru.

do $$
begin
  -- Bez superadmina niko ne bi mogao otvoriti novi kafić, pa se tada ništa ne briše.
  if not exists (select 1 from private.vendor_admins) then
    raise exception 'Nema superadmina. Prvo pokrenite supabase/postavi_superadmina.sql.';
  end if;
end;
$$;

-- Firme i sve što od njih zavisi: lokali, gazde, radnici, PIN-ovi, prijave telefona,
-- artikli, smjene, ulazi, rashodi, ispravke i uplate.
truncate table public.organizations cascade;
truncate table private.login_attempts;

-- Svi nalozi osim superadmina.
delete from auth.users u
where u.id not in (select v.user_id from private.vendor_admins v);

-- Provjera: treba ostati samo superadmin i nula kafića.
select
  (select string_agg(u.email, ', ') from auth.users u) as preostali_nalozi,
  (select count(*) from public.organizations) as firme,
  (select count(*) from public.venues) as lokali,
  (select count(*) from public.shifts) as smjene,
  (select count(*) from public.catalog_images) as slike_u_katalogu;
