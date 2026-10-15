import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Iznos u feninzima; u tabeli se piše kao broj u KM sa dvije decimale.
class XlsxMoney {
  const XlsxMoney(this.amount);

  final int amount;
}

/// Jedan list tabele: podebljano zaglavlje i redovi. Ćelija je String, num,
/// [XlsxMoney] ili null.
class XlsxSheet {
  const XlsxSheet({
    required this.name,
    required this.header,
    required this.rows,
    this.widths = const [],
  });

  final String name;
  final List<String> header;
  final List<List<Object?>> rows;

  /// Širina kolona u znakovima, redom.
  final List<double> widths;
}

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

// Stilovi ćelija: 0 obično, 1 podebljan tekst, 2 iznos.
const _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="$_ns">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>'
    '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// "A", "B", ... "AA" za kolonu od nule.
String _column(int index) {
  var name = '';
  for (var i = index + 1; i > 0; i = (i - 1) ~/ 26) {
    name = String.fromCharCode(65 + (i - 1) % 26) + name;
  }
  return name;
}

String _cell(String ref, Object? value, {bool bold = false}) => switch (value) {
  null => '',
  XlsxMoney(:final amount) =>
    '<c r="$ref" s="2"><v>${(amount / 100).toStringAsFixed(2)}</v></c>',
  num() => '<c r="$ref"><v>$value</v></c>',
  _ =>
    '<c r="$ref" t="inlineStr"${bold ? ' s="1"' : ''}>'
        '<is><t xml:space="preserve">${_escape('$value')}</t></is></c>',
};

String _sheetXml(XlsxSheet sheet) {
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="$_ns">',
  );
  if (sheet.widths.isNotEmpty) {
    out.write('<cols>');
    for (final (i, w) in sheet.widths.indexed) {
      out.write(
        '<col min="${i + 1}" max="${i + 1}" width="$w" customWidth="1"/>',
      );
    }
    out.write('</cols>');
  }
  out.write('<sheetData>');
  final rows = [sheet.header, ...sheet.rows];
  for (final (r, row) in rows.indexed) {
    out.write('<row r="${r + 1}">');
    for (final (c, value) in row.indexed) {
      out.write(_cell('${_column(c)}${r + 1}', value, bold: r == 0));
    }
    out.write('</row>');
  }
  out.write('</sheetData></worksheet>');
  return out.toString();
}

/// Naziv lista bez znakova koje Excel ne dozvoljava, najviše 31 znak.
String _sheetName(String name) {
  final clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  return clean.length > 31 ? clean.substring(0, 31) : clean;
}

/// Pravi .xlsx fajl sa datim listovima.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final zip = Archive();
  void add(String path, String content) =>
      zip.add(ArchiveFile.bytes(path, utf8.encode(content)));

  add(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
  );
  add(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>'
        '${[for (final (i, s) in sheets.indexed) '<sheet name="${_escape(_sheetName(s.name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="$_rel/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="$_rel/styles" Target="styles.xml"/>'
        '</Relationships>',
  );
  add('xl/styles.xml', _styles);
  for (final (i, sheet) in sheets.indexed) {
    add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheet));
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}
