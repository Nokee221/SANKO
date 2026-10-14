import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../data/errors.dart';
import '../data/models.dart';

/// Artikal pročitan iz Excel tabele, prije nego što ga gazda potvrdi.
class ImportedItem {
  const ImportedItem({
    required this.name,
    required this.kind,
    required this.price,
    required this.qty,
  });

  final String name;
  final ItemKind kind;

  /// Cijena u feninzima; null kad je u tabeli nema.
  final int? price;
  final int qty;
}

/// Stanje od ovoliko naviše je brojač aparata, ne komadi (npr. kafa 148687).
const counterThreshold = 10000;

/// Čita artikle iz .xlsx fajla: svaka tabela s kolonama "Naziv" i "Cijena",
/// i više tabela jedna pored druge na istom listu.
List<ImportedItem> itemsFromXlsx(Uint8List bytes) {
  final seen = <String>{};
  return [
    for (final sheet in readXlsx(bytes))
      for (final item in itemsFromRows(sheet))
        if (seen.add(item.name)) item,
  ];
}

/// Artikli iz redova jednog lista, tabelu po tabelu. Ćelija je String, num ili null.
List<ImportedItem> itemsFromRows(List<List<Object?>> rows) {
  final found = <ImportedItem>[];
  var blocks = <(_Block, List<ImportedItem>)>[];
  for (final row in rows) {
    final header = _headerBlocks(row);
    if (header.isNotEmpty) {
      found.addAll(blocks.expand((b) => b.$2));
      blocks = [for (final b in header) (b, [])];
      continue;
    }
    for (final (block, items) in blocks) {
      final item = block.read(row);
      if (item != null) items.add(item);
    }
  }
  return found..addAll(blocks.expand((b) => b.$2));
}

/// Kolone jedne tabele: od kolone naziva do naziva sljedeće tabele u istom redu.
class _Block {
  _Block(this.name);

  final int name;
  int? price;
  int? stock;
  int stockRank = _stockHeaders.length;
  int? total;
  int? used;

  ImportedItem? read(List<Object?> row) {
    final name = _cell(
      row,
      this.name,
    )?.toString().trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (name == null || !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
      return null;
    }
    if (_totalLabels.contains(_fold(name))) return null;
    final price = _num(_cell(row, this.price));
    var qty = _num(_cell(row, stock));
    // Prazan ostatak se računa kao ukupno minus utrošeno, kako tabela i misli.
    if (qty == null && total != null) {
      final sum = _num(_cell(row, total));
      if (sum != null) qty = sum - (_num(_cell(row, used)) ?? 0);
    }
    // Red bez cijene i stanja je bilješka ispod tabele, ne artikal.
    if (price == null && qty == null) return null;
    final count = max(0, (qty ?? 0).round());
    return ImportedItem(
      name: name,
      kind: count >= counterThreshold ? ItemKind.counter : ItemKind.stock,
      price: price == null || price < 0 ? null : (price * 100).round(),
      qty: count,
    );
  }
}

const _nameHeaders = ['naziv', 'artikal', 'artikl', 'artikli', 'proizvod'];
const _priceHeaders = ['cijena', 'cena', 'mpc'];
// Prvo ono što je ostalo na kraju dana; to postaje početno stanje.
const _stockHeaders = ['ostatak danas', 'stanje', 'zaliha', 'kolicina'];
const _totalLabels = {'ukupno', 'total', 'suma', 'svega'};

List<_Block> _headerBlocks(List<Object?> row) {
  final heads = [for (final c in row) c is String ? _fold(c) : ''];
  final names = [
    for (var i = 0; i < heads.length; i++)
      if (_nameHeaders.any(heads[i].startsWith)) i,
  ];
  final blocks = <_Block>[];
  for (var n = 0; n < names.length; n++) {
    final block = _Block(names[n]);
    final end = n + 1 < names.length ? names[n + 1] : heads.length;
    for (var i = names[n] + 1; i < end; i++) {
      final h = heads[i];
      if (h.isEmpty) continue;
      final rank = _stockHeaders.indexWhere(h.contains);
      if (block.price == null && _priceHeaders.any(h.contains)) {
        block.price = i;
      } else if (rank >= 0 && rank < block.stockRank) {
        block.stock = i;
        block.stockRank = rank;
      } else if (h == 'ukupno') {
        block.total = i;
      } else if (h.startsWith('utros')) {
        block.used = i;
      }
    }
    if (block.price != null) blocks.add(block);
  }
  return blocks;
}

Object? _cell(List<Object?> row, int? i) =>
    i == null || i >= row.length ? null : row[i];

double? _num(Object? v) => switch (v) {
  num() => v.toDouble(),
  String() => double.tryParse(v.trim().replaceAll(',', '.')),
  _ => null,
};

/// Mala slova, bez kvačica i suvišnih razmaka, za poređenje zaglavlja.
String _fold(String s) => s
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[čć]'), 'c')
    .replaceAll('š', 's')
    .replaceAll('ž', 'z')
    .replaceAll('đ', 'd')
    .replaceAll(RegExp(r'\s+'), ' ');

/// Listovi .xlsx fajla redom; svaki red je lista ćelija po kolonama.
List<List<List<Object?>>> readXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw SankoException('Fajl nije ispravan Excel (.xlsx).');
  }
  String? text(String path) {
    final data = zip.findFile(path)?.readBytes();
    return data == null ? null : utf8.decode(data);
  }

  final strings = text('xl/sharedStrings.xml');
  final shared = strings == null
      ? const <String>[]
      : [
          for (final si in _children(
            XmlDocument.parse(strings).rootElement,
            'si',
          ))
            _text(si),
        ];

  final sheetName = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$');
  final sheets = [
    for (final f in zip.files)
      if (sheetName.firstMatch(f.name) case final m?)
        (int.parse(m[1]!), f.name),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (sheets.isEmpty) throw SankoException('Fajl nije ispravan Excel (.xlsx).');

  return [
    for (final (_, path) in sheets)
      _readSheet(XmlDocument.parse(text(path)!), shared),
  ];
}

List<List<Object?>> _readSheet(XmlDocument doc, List<String> shared) {
  final rows = <List<Object?>>[];
  for (final row in doc.descendantElements.where(
    (e) => e.name.local == 'row',
  )) {
    final cells = <Object?>[];
    for (final c in _children(row, 'c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? cells.length : _column(ref);
      while (cells.length <= col) {
        cells.add(null);
      }
      final v = _children(c, 'v').firstOrNull?.innerText;
      cells[col] = switch (c.getAttribute('t')) {
        's' => v == null ? null : shared[int.parse(v)],
        'inlineStr' => _text(c),
        'str' => v,
        'b' || 'e' => null,
        _ => v == null ? null : num.tryParse(v) ?? v,
      };
    }
    rows.add(cells);
  }
  return rows;
}

Iterable<XmlElement> _children(XmlElement e, String local) =>
    e.childElements.where((c) => c.name.local == local);

/// Tekst ćelije ili dijeljenog teksta, bez fonetskih dodataka (rPh).
String _text(XmlElement e) => e.descendantElements
    .where((t) => t.name.local == 't' && t.parentElement?.name.local != 'rPh')
    .map((t) => t.innerText)
    .join();

/// "AB12" -> 27.
int _column(String ref) {
  var col = 0;
  for (final unit in ref.codeUnits) {
    if (unit < 65 || unit > 90) break;
    col = col * 26 + unit - 64;
  }
  return col - 1;
}
