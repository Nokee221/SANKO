import 'models.dart';

/// Artikli i stanja iz primjera knjige šanka, za isprobavanje: naziv, vrsta, cijena, stanje.
/// Kafa i nes iz aparata se vode u gramima; gramaža porcije je u [demoPortions].
const demoItems = <(String, ItemKind, int, int)>[
  ('KAFA', ItemKind.counter, 250, 145000),
  ('NES APARAT', ItemKind.counter, 350, 50000),
  ('KAPUCINO', ItemKind.stock, 350, 40),
  ('ČAJ', ItemKind.stock, 300, 214),
  ('NES', ItemKind.stock, 350, 65),
  ('TOPLA ČOKOLADA', ItemKind.stock, 450, 30),
  ('JAGODA', ItemKind.stock, 350, 41),
  ('JABUKA', ItemKind.stock, 350, 57),
  ('RIBIZLA', ItemKind.stock, 350, 50),
  ('BRESKVA', ItemKind.stock, 350, 59),
  ('ĐUS', ItemKind.stock, 350, 56),
  ('LEDENI ČAJ', ItemKind.stock, 350, 28),
  ('KOLA', ItemKind.stock, 350, 77),
  ('FANTA', ItemKind.stock, 350, 42),
  ('SPRITE', ItemKind.stock, 350, 32),
  ('TONIK', ItemKind.stock, 350, 72),
  ('COCKTA', ItemKind.stock, 350, 29),
  ('ORANGINA', ItemKind.stock, 400, 10),
  ('RED BULL', ItemKind.stock, 500, 23),
  ('SENZACIJA', ItemKind.stock, 300, 62),
  ('KISELA', ItemKind.stock, 250, 107),
  ('VODA', ItemKind.stock, 250, 38),
  ('LIMUN', ItemKind.stock, 350, 72),
  ('CEDEVITA', ItemKind.stock, 300, 74),
  ('HEINEKEN', ItemKind.stock, 450, 71),
  ('STELLA', ItemKind.stock, 450, 31),
  ('BECKS', ItemKind.stock, 450, 10),
  ('SOMERSBY', ItemKind.stock, 450, 29),
  ('RADLER', ItemKind.stock, 400, 2),
  ('SARAJEVSKO', ItemKind.stock, 400, 23),
  ('TOČENO', ItemKind.stock, 350, 32),
  ('GRAŠEVINA', ItemKind.stock, 600, 26),
  ('VRANAC', ItemKind.stock, 600, 12),
];

/// Grama po porciji za probne artikle koji se vode u gramima.
const demoPortions = {'KAFA': 20, 'NES APARAT': 15};
