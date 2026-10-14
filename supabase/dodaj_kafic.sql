-- Otvara novog kupca: firmu, njen prvi lokal i gazdu. Pokreće se u Supabase SQL Editoru.
-- Prije pokretanja: nalog gazde mora postojati (Authentication -> Users -> Add user).
-- Rezultat je kod lokala, koji konobari jednom ukucaju na telefonu.
-- Za sljedeći kafić promijenite četiri vrijednosti ispod.

select vendor.create_customer(
  'Korzo',                 -- naziv firme
  'Centar',                -- naziv lokala
  'cosabrat6@gmail.com',   -- e-mail gazde
  current_date + 30        -- plaćeno do
) as kod_lokala;
