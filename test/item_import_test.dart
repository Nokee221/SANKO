import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/errors.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/domain/item_import.dart';

/// Najmanji .xlsx: dijeljeni tekstovi i jedan list s datim ćelijama.
Uint8List xlsx(Map<String, Object> cells) {
  final strings = <String>[];
  final rows = <int, StringBuffer>{};
  for (final MapEntry(key: ref, value: v) in cells.entries) {
    final row = int.parse(ref.replaceAll(RegExp('[A-Z]'), ''));
    final xml = v is String
        ? '<c r="$ref" t="s"><v>${(strings..add(v)).length - 1}</v></c>'
        : '<c r="$ref"><v>$v</v></c>';
    (rows[row] ??= StringBuffer()).write(xml);
  }
  const ns =
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  final sheet =
      '<worksheet $ns><sheetData>'
      '${[for (final MapEntry(key: r, value: c) in rows.entries) '<row r="$r">$c</row>'].join()}'
      '</sheetData></worksheet>';
  final shared =
      '<sst $ns>${strings.map((s) => '<si><t>$s</t></si>').join()}</sst>';
  final zip = Archive()
    ..add(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(shared)))
    ..add(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode(sheet)));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  test('čita dvije tabele jednu pored druge, kao knjiga šanka', () {
    final items = itemsFromXlsx(
      xlsx({
        for (final (col, h) in [
          ('A', 'Rb'),
          ('B', 'Naziv artikla'),
          ('C', 'Ostatak jucer'),
          ('D', 'Primljeno'),
          ('E', 'Ukupno'),
          ('F', 'Utroseno'),
          ('G', 'Ostatak danas'),
          ('H', 'Cijena'),
          ('I', 'Iznos'),
          ('K', 'Rb'),
          ('L', 'Naziv artikla'),
          ('M', 'Ostatak jucer'),
          ('O', 'Ukupno'),
          ('P', 'Utroseno'),
          ('Q', 'Ostatak danas'),
          ('R', 'Cijena'),
        ])
          '${col}1': h,
        'B2': 'KAFA',
        'E2': 148687,
        'G2': 149091,
        'H2': 2.5,
        'L2': 'TOCENO ',
        'O2': 32,
        'P2': 2,
        'R2': 3.5,
        'B3': 'CAJ  ',
        'E3': 214,
        'G3': 207,
        'H3': 3,
        'L3': 'GIN',
        'O3': 0,
        'R3': 3.5,
        'B4': 'SULTAN',
        'E4': 0,
        'H4': '3,50',
        'L4': 'BEZ CIJENE',
        'Q4': 5,
        'B6': '30.07.2025',
        'E7': 'SANK',
        'F7': 2054,
      }),
    );
    String show(ImportedItem i) =>
        '${i.name} ${i.kind.name} ${i.price} ${i.qty}';
    expect(items.map(show), [
      'KAFA counter 250 149091',
      'CAJ stock 300 207',
      'SULTAN stock 350 0',
      'TOCENO stock 350 30',
      'GIN stock 350 0',
      'BEZ CIJENE stock null 5',
    ]);
  });

  test('isti naziv u više tabela se uzima jednom', () {
    final items = itemsFromXlsx(
      xlsx({
        'A1': 'Naziv',
        'B1': 'Cijena',
        'C1': 'Stanje',
        'A2': 'KOLA',
        'B2': 3.5,
        'C2': 10,
        'A3': 'kola',
        'B3': 4,
        'C3': 1,
      }),
    );
    expect(items.single.price, 350);
    expect(items.single.kind, ItemKind.stock);
  });

  test('fajl koji nije Excel daje jasnu poruku', () {
    expect(
      () => itemsFromXlsx(Uint8List.fromList(utf8.encode('nije excel'))),
      throwsA(isA<SankoException>()),
    );
  });
}
