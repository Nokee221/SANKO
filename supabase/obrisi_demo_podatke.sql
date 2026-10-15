-- Briše probne smjene koje je napravio supabase/demo_podaci.sql (sa ulazima, rashodima i
-- ispravkama). Konobari, artikli i prave smjene ostaju. Pokreće se u Supabase SQL Editoru.

delete from public.shifts s where s.id::text like 'de3d0000-%';

-- Provjera: treba ispisati nulu.
select count(*) as preostale_probne_smjene
from public.shifts s
where s.id::text like 'de3d0000-%';
