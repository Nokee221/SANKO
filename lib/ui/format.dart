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

/// Čita "3,5", "3.50" ili "3" kao feninge; null ako nije ispravan iznos.
int? parseMoney(String input) {
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(input.trim());
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
