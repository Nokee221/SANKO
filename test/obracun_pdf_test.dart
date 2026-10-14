import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/domain/obracun.dart';
import 'package:sanko/ui/admin/obracun_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'obračun se pretvara u PDF sa našim slovima, rashodom i ispravkama',
    () async {
      final bytes = await buildObracunPdf(
        venueName: 'Korzo, Centar',
        title: 'Obračun smjene 1, 14.10.2026',
        subtitle: 'Kenan, 07:00–15:00',
        obracun: Obracun(
          lines: [
            for (final (i, name) in [
              'KAFA',
              'ĐUS',
              'TOPLA ČOKOLADA',
              'GRAŠEVINA',
            ].indexed)
              ObracunLine.forShift(
                itemId: '$i',
                name: name,
                kind: i == 0 ? ItemKind.counter : ItemKind.stock,
                price: 350,
                opening: i == 0 ? 148687 : 40,
                received: i == 1 ? 24 : 0,
                closing: i == 0 ? 149091 : 30,
              ),
          ],
          expenses: 550,
        ),
        expenses: [
          (
            'Kenan',
            Expense(
              id: 'e1',
              shiftId: 's1',
              description: 'Konzum, mlijeko',
              amount: 300,
              createdAt: DateTime(2026, 10, 14, 9, 30),
            ),
          ),
        ],
        corrections: [
          ShiftCorrection(
            shiftId: 's1',
            itemName: 'ĐUS',
            isClosing: true,
            oldValue: 35,
            newValue: 30,
            note: 'Ponovo prebrojano',
            correctedAt: DateTime(2026, 10, 14, 16),
          ),
        ],
        createdAt: DateTime(2026, 10, 14, 17),
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
      final out = Platform.environment['SANKO_PDF'];
      if (out != null) await File(out).writeAsBytes(bytes);
    },
  );
}
