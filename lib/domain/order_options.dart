/// Jedan korak izbora pri kucanju artikla, npr. dužina kafe.
class OptionStep {
  const OptionStep(this.title, this.choices);

  final String title;
  final List<String> choices;
}

const _coffee = [
  OptionStep('Dužina', ['Kraća', 'Duža', 'Produžena']),
  OptionStep('Mlijeko', ['Sa mlijekom', 'Bez mlijeka', 'Sa šlagom']),
];

const _tea = [
  OptionStep('Vrsta čaja', [
    'Menta',
    'Šipak',
    'Kamilica',
    'Zeleni',
    'Crni',
    'Voćni',
    'Planinski',
    'Lipa',
  ]),
];

/// Izbori koje konobar bira kad tapne artikal; prazno znači da artikal nema izbora.
/// Za sada fiksno: kafa (dužina pa mlijeko) i čaj (vrsta).
List<OptionStep> optionsFor(String itemName) => switch (_plain(itemName)) {
  'KAFA' => _coffee,
  'CAJ' => _tea,
  _ => const [],
};

/// Naziv bez kvačica i razmaka na krajevima, da "Čaj", "ČAJ" i "CAJ" budu isto.
String _plain(String name) => name
    .trim()
    .toUpperCase()
    .replaceAll('Č', 'C')
    .replaceAll('Ć', 'C')
    .replaceAll('Š', 'S')
    .replaceAll('Ž', 'Z')
    .replaceAll('Đ', 'DJ');
