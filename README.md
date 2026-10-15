# Šanko

Digitalna knjiga šanka za kafiće i restorane: konobar na telefonu vodi ulaz, rashod i stanje
na kraju smjene i predaje novac, a gazda na računaru ili telefonu vidi obračun, manjkove, izvještaje i
narudžbu, i dobija poruku na Telegram kad se smjena zaključi. Jedna baza služi više kafića;
pretplate vodi superadmin. Šta aplikacija radi, za prezentaciju kupcima: `docs/PREZENTACIJA.md`.

## Dijelovi

| Dio | Gdje | Ko koristi |
|---|---|---|
| Aplikacija za telefon | Android (`flutter run` na telefonu) | pri prvom pokretanju bira se uloga. Konobar: kod lokala, PIN, ULAZ, RASHOD, STANJE, PREDAJA (kuhinja, gotovina, kartice); radi i bez interneta. Gazda: prijava e-mailom i isti admin panel kao na računaru, prilagođen telefonu |
| Admin panel | Windows (`flutter run -d windows`) ili pregledač (`flutter run -d chrome -t lib/main_admin.dart`) | gazda: obračun sa predajom i manjkom, mjesečni izvještaj i izvještaj po konobaru (Excel), prosjek, narudžba (Viber, PDF), artikli (uvoz iz Excela, minimum), radnici, Telegram obavještenja, PDF, ispravke |
| Panel superadmina | ista desktop aplikacija, prijava superadmin nalogom | prodavac: kafići, pretplate, uplate |
| Server | Supabase (Postgres, prijava, serverske funkcije) | sve gore |

## Kod

- `lib/data`, `lib/domain`: lokalna baza telefona, obračun, prosjeci i zaliha.
- `lib/sync`: veza sa Supabaseom i slanje smjena s telefona.
- `lib/ui/waiter`, `lib/ui/admin`, `lib/ui/vendor`: ekrani konobara, gazde i superadmina.
- `supabase/migrations`: šema baze, redom kako se pokreće.
- `supabase/functions/create-owner`: serverska funkcija koja pravi nalog gazde za novi kafić.
- `supabase/functions/notify-shift`, `telegram-webhook`: obavještenje gazdi na Telegram i povezivanje bota.
- `test`: testovi; `flutter test`.

## Postavljanje novog Supabase projekta

1. U SQL Editoru pokrenuti sve fajlove iz `supabase/migrations`, redom po nazivu.
2. Napraviti nalog superadmina (Authentication → Users → Add user) i pokrenuti
   `supabase/postavi_superadmina.sql` sa njegovim e-mailom.
3. Postaviti serversku funkciju `create-owner` (Edge Functions → Deploy a new function).
4. Po želji ubaciti katalog slika: `python tool/slike_u_sql.py`, pa pokrenuti `supabase/slike.sql`.
   Slike za artikle iz Excel tabele kafića skida `python tool/skini_slike.py "tabela.xlsx"`
   (treba `pip install openpyxl Pillow requests`); ona na kraju sama napravi `supabase/slike.sql`.
5. Upisati adresu projekta i objavljeni ključ u `lib/config.dart`.
6. Po želji podesiti Telegram obavještenja (ispod).

## Telegram obavještenja

Gazda dobija poruku čim se smjena zaključi: šank, kuhinja, rashod, predano, manjak i artikli
prebrojani više nego što je moglo biti. Podešava se jednom za cijeli server:

1. U Telegramu otvoriti @BotFather, poslati `/newbot` i sačuvati token koji vrati.
2. U Supabaseu, Edge Functions → Secrets, dodati `TELEGRAM_BOT_TOKEN` (token) i
   `TELEGRAM_WEBHOOK_SECRET` (bilo koji slučajan tekst od bar 16 znakova).
3. Postaviti funkcije `notify-shift` i `telegram-webhook` (kod iz `supabase/functions`) i u
   podešavanjima obje isključiti **Verify JWT**: prvu budi baza, drugu Telegram, bez prijave.
4. U pregledaču jednom otvoriti
   `https://<projekat>.supabase.co/functions/v1/telegram-webhook?setup=<TELEGRAM_WEBHOOK_SECRET>`.
   Treba pisati "Telegram je podešen: @ime_bota".
5. Gazda u admin panelu otvori **Obavještenja → Poveži Telegram** i u Telegramu pritisne Start.

Baza budi funkciju preko `pg_net`, koji uključuje migracija `20261020000000_predaja_izvjestaji.sql`.

`supabase/obrisi_sve_podatke.sql` briše sve kafiće i naloge osim superadmina; koristi se samo za
ponovno testiranje od nule.

## Licence

Font Manrope: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
Ikone na probnim slikama artikala: Material Icons, Apache License 2.0.
Fotografije artikala: Creative Commons i javno dobro, preko Openverse; autor i licenca svake
slike su u `supabase/slike/IZVORI.md`.
