-- Briše probne smjene koje je napravio supabase/demo_podaci.sql (sa ulazima, rashodima i
-- ispravkama) i probne narudžbe iz supabase/demo_narudzbe.sql. Konobari, stolovi, artikli,
-- prave smjene i prave narudžbe ostaju. Pokreće se u Supabase SQL Editoru.

delete from public.shifts s where s.id::text like 'de3d0000-%';
delete from public.orders o where o.id::text like 'de3d0001-%';

-- Provjera: treba ispisati dvije nule.
select
  (select count(*) from public.shifts s where s.id::text like 'de3d0000-%') as preostale_probne_smjene,
  (select count(*) from public.orders o where o.id::text like 'de3d0001-%') as preostale_probne_narudzbe;
