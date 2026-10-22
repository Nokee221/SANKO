# Promjene baze

Skripte koje treba pokrenuti u Supabase SQL Editoru kad se baza dovodi na novu verziju
aplikacije. Pokreću se redom, svaka jednom. Nova baza od nule: sve iz `migrations/`, redom
po nazivu (vidi README).

| Datum | Skripta | Šta donosi | Obavezno |
|---|---|---|---|
| 2026-10-20 | `migrations/20261020000000_predaja_izvjestaji.sql` | predaja novca, kuhinja, izvještaji, minimalna zaliha, Telegram | da |
| 2026-10-21 | `migrations/20261021000000_narudzbe.sql` | uloge radnika (konobar, šank), stolovi, narudžbe sa stola na šank | da, prije nove aplikacije |
| 2026-10-21 | `obrisi_sve_podatke.sql` | briše sve osim superadmina; dopunjena za Telegram tabele | samo za test od nule |

Bez `20261021000000_narudzbe.sql` aplikacija radi, ali NARUDŽBA na telefonu javlja grešku,
a gazda ne može birati ulogu radnika ni unositi stolove.
