import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Ispravke zaključenih smjena; na telefonu se ne koriste, ali baza ima isti oblik svuda.
const _corrections = '''
  CREATE TABLE corrections (
    id TEXT PRIMARY KEY,
    shift_id TEXT NOT NULL REFERENCES shifts (id),
    item_name TEXT NOT NULL,
    field TEXT NOT NULL,
    old_value INTEGER,
    new_value INTEGER NOT NULL,
    note TEXT,
    corrected_at INTEGER NOT NULL
  )''';

// Stolovi lokala; na telefonu se ne koriste, ali lokalni admin u testovima ih uređuje.
const _tables = '''
  CREATE TABLE venue_tables (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
  )''';

const _schema = [
  '''
  CREATE TABLE workers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    pin TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    role TEXT NOT NULL DEFAULT 'konobar'
  )''',
  '''
  CREATE TABLE items (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    price INTEGER NOT NULL,
    initial_qty INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL,
    image_id TEXT,
    min_qty INTEGER,
    par_qty INTEGER
  )''',
  '''
  CREATE TABLE shifts (
    id TEXT PRIMARY KEY,
    worker_id TEXT NOT NULL REFERENCES workers (id),
    business_date TEXT NOT NULL,
    seq INTEGER NOT NULL,
    opened_at INTEGER NOT NULL,
    closed_at INTEGER,
    dirty INTEGER NOT NULL DEFAULT 0,
    kitchen INTEGER,
    cash INTEGER,
    card INTEGER
  )''',
  'CREATE INDEX shifts_business_date_idx ON shifts (business_date)',
  // Naziv, vrsta i cijena se kopiraju pri otvaranju smjene,
  // da kasnija promjena cjenovnika ne mijenja stare obračune.
  '''
  CREATE TABLE shift_lines (
    shift_id TEXT NOT NULL REFERENCES shifts (id),
    item_id TEXT NOT NULL REFERENCES items (id),
    item_name TEXT NOT NULL,
    kind TEXT NOT NULL,
    price INTEGER NOT NULL,
    sort_order INTEGER NOT NULL,
    opening_qty INTEGER NOT NULL,
    closing_qty INTEGER,
    sold_qty INTEGER,
    PRIMARY KEY (shift_id, item_id)
  )''',
  // Jedan ulaz je jedna dostava: unosi se, pa zaključi. closed_at NULL znači da je još u unosu.
  '''
  CREATE TABLE receipts (
    id TEXT PRIMARY KEY,
    shift_id TEXT NOT NULL REFERENCES shifts (id),
    created_at INTEGER NOT NULL,
    closed_at INTEGER
  )''',
  '''
  CREATE TABLE receipt_lines (
    receipt_id TEXT NOT NULL REFERENCES receipts (id),
    item_id TEXT NOT NULL REFERENCES items (id),
    qty INTEGER NOT NULL,
    PRIMARY KEY (receipt_id, item_id)
  )''',
  '''
  CREATE TABLE expenses (
    id TEXT PRIMARY KEY,
    shift_id TEXT NOT NULL REFERENCES shifts (id),
    description TEXT NOT NULL,
    amount INTEGER NOT NULL,
    created_at INTEGER NOT NULL
  )''',
  // Podešavanja telefona: kod lokala i radnik za kojeg je uređaj prijavljen na serveru.
  'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
  // Slike artikala, sačuvane na uređaju da rade i bez interneta.
  'CREATE TABLE images (id TEXT PRIMARY KEY, name TEXT NOT NULL, data BLOB NOT NULL)',
  _corrections,
  _tables,
];

Future<void> createSchema(Database db) async {
  for (final statement in _schema) {
    await db.execute(statement);
  }
}

Future<Database> openAppDatabase() async {
  final options = OpenDatabaseOptions(
    version: 7,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, _) => createSchema(db),
    onUpgrade: (db, from, _) async {
      if (from < 2) {
        await db.execute(
          'ALTER TABLE shifts ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
        );
      }
      if (from < 3) {
        await db.execute('ALTER TABLE items ADD COLUMN image_id TEXT');
        await db.execute(
          'CREATE TABLE images (id TEXT PRIMARY KEY, name TEXT NOT NULL, data BLOB NOT NULL)',
        );
      }
      if (from < 4) await db.execute(_corrections);
      if (from < 5) {
        // Kuhinja i predaja novca uz smjenu, minimum i narudžba uz artikal.
        for (final column in ['kitchen', 'cash', 'card']) {
          await db.execute('ALTER TABLE shifts ADD COLUMN $column INTEGER');
        }
        for (final column in ['min_qty', 'par_qty']) {
          await db.execute('ALTER TABLE items ADD COLUMN $column INTEGER');
        }
        // Ispravka predaje stare smjene nema staru vrijednost.
        if (from >= 4) {
          await db.execute('ALTER TABLE corrections RENAME TO corrections_old');
          await db.execute(_corrections);
          await db.execute(
            'INSERT INTO corrections SELECT * FROM corrections_old',
          );
          await db.execute('DROP TABLE corrections_old');
        }
      }
      if (from < 6) {
        // Konobar upisuje prodano; ostatak se iz njega računa.
        await db.execute('ALTER TABLE shift_lines ADD COLUMN sold_qty INTEGER');
      }
      if (from < 7) {
        // Uloga radnika i stolovi za narudžbe.
        await db.execute(
          "ALTER TABLE workers ADD COLUMN role TEXT NOT NULL DEFAULT 'konobar'",
        );
        await db.execute(_tables);
      }
    },
  );
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    return databaseFactoryFfi.openDatabase(
      p.join(dir.path, 'sanko.db'),
      options: options,
    );
  }
  return databaseFactory.openDatabase(
    p.join(await getDatabasesPath(), 'sanko.db'),
    options: options,
  );
}
