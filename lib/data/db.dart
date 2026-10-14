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
    old_value INTEGER NOT NULL,
    new_value INTEGER NOT NULL,
    note TEXT,
    corrected_at INTEGER NOT NULL
  )''';

const _schema = [
  '''
  CREATE TABLE workers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    pin TEXT NOT NULL,
    active INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
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
    image_id TEXT
  )''',
  '''
  CREATE TABLE shifts (
    id TEXT PRIMARY KEY,
    worker_id TEXT NOT NULL REFERENCES workers (id),
    business_date TEXT NOT NULL,
    seq INTEGER NOT NULL,
    opened_at INTEGER NOT NULL,
    closed_at INTEGER,
    dirty INTEGER NOT NULL DEFAULT 0
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
];

Future<void> createSchema(Database db) async {
  for (final statement in _schema) {
    await db.execute(statement);
  }
}

Future<Database> openAppDatabase() async {
  final options = OpenDatabaseOptions(
    version: 4,
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
