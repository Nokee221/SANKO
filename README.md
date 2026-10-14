# Šanko

Digitalna knjiga šanka za kafiće i restorane: konobar na telefonu vodi ulaz, rashod i stanje
na kraju smjene, a gazda na računaru vidi obračun po danu i smjeni. Jedna baza služi više
kafića; pretplate vodi superadmin.

## Dijelovi

| Dio | Gdje | Ko koristi |
|---|---|---|
| Aplikacija za konobara | Android (`flutter run` na telefonu) | konobar: kod lokala, PIN, ULAZ, RASHOD, STANJE; radi i bez interneta |
| Admin panel | Windows (`flutter run -d windows`) ili pregledač (`flutter run -d chrome -t lib/main_admin.dart`) | gazda: obračun, prosjek, artikli, radnici, PDF, ispravke |
| Panel superadmina | ista desktop aplikacija, prijava superadmin nalogom | prodavac: kafići, pretplate, uplate |
| Server | Supabase (Postgres, prijava, serverska funkcija) | sve gore |

## Kod

- `lib/data`, `lib/domain`: lokalna baza telefona, obračun, prosjeci i zaliha.
- `lib/sync`: veza sa Supabaseom i slanje smjena s telefona.
- `lib/ui/waiter`, `lib/ui/admin`, `lib/ui/vendor`: ekrani konobara, gazde i superadmina.
- `supabase/migrations`: šema baze, redom kako se pokreće.
- `supabase/functions/create-owner`: serverska funkcija koja pravi nalog gazde za novi kafić.
- `test`: testovi; `flutter test`.

## Postavljanje novog Supabase projekta

1. U SQL Editoru pokrenuti sve fajlove iz `supabase/migrations`, redom po nazivu.
2. Napraviti nalog superadmina (Authentication → Users → Add user) i pokrenuti
   `supabase/postavi_superadmina.sql` sa njegovim e-mailom.
3. Postaviti serversku funkciju `create-owner` (Edge Functions → Deploy a new function).
4. Po želji ubaciti katalog slika: `python tool/slike_u_sql.py`, pa pokrenuti `supabase/slike.sql`.
5. Upisati adresu projekta i objavljeni ključ u `lib/config.dart`.

`supabase/obrisi_sve_podatke.sql` briše sve kafiće i naloge osim superadmina; koristi se samo za
ponovno testiranje od nule.

## Licence

Font Manrope: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
Ikone na probnim slikama artikala: Material Icons, Apache License 2.0.
