import '../data/models.dart';

const _weekdays = [
  'ponedjeljak',
  'utorak',
  'srijeda',
  'četvrtak',
  'petak',
  'subota',
  'nedjelja',
];

/// Feninzi u zapis "1.010,00".
String fmtMoney(int amount) {
  final negative = amount < 0;
  final abs = amount.abs();
  final whole = (abs ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$grouped,${(abs % 100).toString().padLeft(2, '0')}';
}

String fmtKm(int amount) => '${fmtMoney(amount)} KM';

/// Čita "3,5", "3.50", "3" ili "1.167,50" kao feninge; null ako nije ispravan iznos.
int? parseMoney(String input) {
  var text = input.replaceAll(RegExp(r'\s'), '');
  // Tačka za hiljade, kako se iznos i ispisuje: "1.167,50" ili "1.500".
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d{1,2})?$').hasMatch(text)) {
    text = text.replaceAll('.', '');
  }
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final cents = (match.group(2) ?? '').padRight(2, '0');
  return int.parse(match.group(1)!) * 100 + int.parse(cents);
}

String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Prosjek sa jednom decimalom: "5,2".
String fmtAvg(double value) => value.toStringAsFixed(1).replaceAll('.', ',');

/// Bosanski oblik riječi uz broj: 1 dan, 2 dana, 5 dana; 21 dan, 22 dana.
String plural(int n, String one, String few, String many) {
  final lastTwo = n % 100;
  final last = n % 10;
  if (last == 1 && lastTwo != 11) return one;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return few;
  return many;
}

/// Ispravka kao tekst: "ostatak 35 → 30" ili "gotovina 100,00 → 120,00 KM".
String correctionText(ShiftCorrection c) {
  String value(int? v) => v == null
      ? '–'
      : c.field.isMoney
      ? fmtMoney(v)
      : '$v';
  return '${c.field.label} ${value(c.oldValue)} → ${value(c.newValue)}'
      '${c.field.isMoney ? ' KM' : ''}';
}
