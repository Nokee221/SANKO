-- BRIŠE SVE SMJENE: stavke smjena, ulaze, rashode, predaje, ispravke, obavještenja o
-- smjenama i sve narudžbe sa stolova, u svim kafićima.
-- Ostaju kafići, lokali, gazde, radnici i PIN-ovi, artikli, stolovi, slike i uplate.
-- Sljedeća smjena počinje od početnog stanja artikla (Artikli → Uredi).
-- Ne može se poništiti. Pokreće se u Supabase SQL Editoru.
--
-- Telefon pamti svoju smjenu: poslije ovoga konobar se odjavi i ponovo prijavi, ili se
-- obrišu podaci aplikacije na telefonu.

-- Smjene i sve što od njih zavisi (stavke, ulazi, rashodi, ispravke, red obavještenja).
truncate table public.shifts cascade;

-- Narudžbe sa stolova (i njihove stavke).
truncate table public.orders cascade;

-- Provjera: smjena i narudžbi treba biti nula, a artikli i radnici ostaju.
select
  (select count(*) from public.shifts) as smjene,
  (select count(*) from public.orders) as narudzbe,
  (select count(*) from public.items where active) as artikli,
  (select count(*) from public.workers where active) as radnici,
  (select count(*) from public.venues) as lokali;
