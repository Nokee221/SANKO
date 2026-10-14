import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models.dart';
import '../../domain/obracun.dart';
import '../format.dart';

/// Obračun kao PDF dokument, u obliku knjige šanka: zbirovi, tabela, rashod i ispravke.
Future<Uint8List> buildObracunPdf({
  required String venueName,
  required String title,
  required String subtitle,
  required Obracun obracun,
  required List<(String worker, Expense expense)> expenses,
  required List<ShiftCorrection> corrections,
  DateTime? createdAt,
}) async {
  Future<pw.Font> font(String file) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  final regular = await font('Manrope-400.ttf');
  final bold = await font('Manrope-700.ttf');
  final logo = pw.MemoryImage(
    (await rootBundle.load('assets/brand/logo.png')).buffer.asUint8List(),
  );
  final created = createdAt ?? DateTime.now();

  const navy = PdfColor.fromInt(0xFF0F1B33);
  const muted = PdfColor.fromInt(0xFF5F6878);
  const line = PdfColor.fromInt(0xFFE1E5EC);
  const paper = PdfColor.fromInt(0xFFF3F5F8);

  final doc = pw.Document(
    title: '$title, $venueName',
    author: 'Šanko',
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  pw.Widget stat(String label, int amount, {bool highlight = false}) =>
      pw.Container(
        width: 170,
        padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: pw.BoxDecoration(
          color: highlight ? navy : PdfColors.white,
          border: pw.Border.all(color: highlight ? navy : line),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                color: highlight ? const PdfColor.fromInt(0xFFC9A45C) : muted,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${fmtMoney(amount)} KM',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                color: highlight ? PdfColors.white : navy,
              ),
            ),
          ],
        ),
      );

  pw.Widget section(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
  );

  String qty(int? v) => v == null ? '–' : '$v';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => context.pageNumber > 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Image(logo, width: 34, height: 34),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Šanko',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: navy,
                        ),
                      ),
                      pw.Text(
                        venueName,
                        style: const pw.TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                  pw.Spacer(),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        title,
                        style: pw.TextStyle(
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        subtitle,
                        style: const pw.TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Napravljeno u aplikaciji Šanko, ${fmtDate(created)} u ${fmtTime(created)}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Strana ${context.pageNumber} od ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Row(
          children: [
            stat('Šank', obracun.sank),
            pw.SizedBox(width: 10),
            stat('Rashod', obracun.expenses),
            pw.SizedBox(width: 10),
            stat('Ukupno', obracun.total, highlight: true),
          ],
        ),
        if (!obracun.isComplete)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Smjena još nije zaključena, pa utrošeno i iznos nisu konačni.',
              style: const pw.TextStyle(fontSize: 9, color: muted),
            ),
          ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: [
            '#',
            'Naziv artikla',
            'Ostatak prije',
            'Primljeno',
            'Ukupno',
            'Utrošeno',
            'Ostatak',
            'Cijena',
            'Iznos',
          ],
          data: [
            for (final (i, l) in obracun.lines.indexed)
              [
                '${i + 1}',
                l.name,
                '${l.opening}',
                l.received == 0 ? '' : '${l.received}',
                '${l.total}',
                qty(l.consumed),
                qty(l.closing),
                fmtMoney(l.price),
                l.amount == null || l.amount == 0 ? '–' : fmtMoney(l.amount!),
              ],
          ],
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: line, width: 0.5),
            bottom: pw.BorderSide(color: line, width: 0.5),
          ),
          headerDecoration: const pw.BoxDecoration(color: paper),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: muted,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          columnWidths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(2.4),
            for (var c = 2; c <= 8; c++) c: const pw.FlexColumnWidth(),
          },
          headerAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            for (var c = 2; c <= 8; c++) c: pw.Alignment.centerRight,
          },
          cellAlignments: {
            0: pw.Alignment.centerRight,
            1: pw.Alignment.centerLeft,
            for (var c = 2; c <= 8; c++) c: pw.Alignment.centerRight,
          },
        ),
        if (expenses.isNotEmpty) ...[
          section('Rashod po stavkama'),
          for (final (worker, e) in expenses)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 50,
                    child: pw.Text(
                      fmtTime(e.createdAt),
                      style: const pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ),
                  pw.SizedBox(
                    width: 90,
                    child: pw.Text(
                      worker,
                      style: const pw.TextStyle(fontSize: 9, color: muted),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      e.description,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Text(
                    fmtMoney(e.amount),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (corrections.isNotEmpty) ...[
          section('Ispravke'),
          for (final c in corrections)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                '${fmtDate(c.correctedAt)} ${fmtTime(c.correctedAt)}   '
                '${c.itemName}: ${c.isClosing ? 'ostatak' : 'primljeno'} '
                '${c.oldValue} → ${c.newValue}'
                '${c.note == null ? '' : '   (${c.note})'}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
        ],
      ],
    ),
  );
  return doc.save();
}
