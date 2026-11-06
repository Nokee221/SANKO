# Promjene baze

Skripte koje treba pokrenuti u Supabase SQL Editoru kad se baza dovodi na novu verziju
aplikacije. Pokreću se redom, svaka jednom. Nova baza od nule: sve iz `migrations/`, redom
po nazivu (vidi README).

| Datum | Skripta | Šta donosi | Obavezno |
|---|---|---|---|
| 2026-10-20 | `migrations/20261020000000_predaja_izvjestaji.sql` | predaja novca, kuhinja, izvještaji, minimalna zaliha, Telegram | da |
| 2026-10-21 | `migrations/20261021000000_narudzbe.sql` | uloge radnika (konobar, šank), stolovi, narudžbe sa stola na šank | da, prije nove aplikacije |
| 2026-11-03 | `migrations/20261022000000_kafa_grami.sql` | kafa i nes u gramima: gramaža porcije uz artikal, prodano = porcije, sa zalihe se skida porcije × gramaža; ulaz kafe u gramima | da, prije nove aplikacije |
| 2026-11-05 | `migrations/20261023000000_tudja_smjena.sql` | telefon pita server je li gazda zaključio tuđu smjenu ostalu otvorenu na telefonu, da sljedeći konobar može početi | da, prije nove aplikacije |
| 2026-11-06 | `migrations/20261024000000_ispravke_sinhronizacije.sql` | prijava ograničena i po IP adresi, telefon ne zaboravlja ispravan PIN kad je prijava zaključana; smjenu vodi jedan telefon; jasne greške kad je gazda zaključio smjenu ili dodao artikal pri zaključenju; anomalija kafe u gramima | da, prije nove aplikacije |
| 2026-10-21 | `obrisi_sve_podatke.sql` | briše sve osim superadmina; dopunjena za Telegram tabele | samo za test od nule |

Bez `20261021000000_narudzbe.sql` aplikacija radi, ali NARUDŽBA na telefonu javlja grešku,
a gazda ne može birati ulogu radnika ni unositi stolove.

Poslije `20261022000000_kafa_grami.sql` gazda u Artiklima za kafu i nes upisuje zalihu u
gramima i gramažu jedne porcije (npr. 20 g). Stare probne smjene vođene po brojaču aparata
tada daju pogrešno utrošeno; za test od nule ih obrišite sa `obrisi_sve_podatke.sql`.
