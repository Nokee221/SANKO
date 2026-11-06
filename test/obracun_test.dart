import 'package:flutter_test/flutter_test.dart';
import 'package:sanko/data/models.dart';
import 'package:sanko/domain/obracun.dart';

void main() {
  ObracunLine kafa({required int closing}) => ObracunLine.forShift(
    itemId: 'kafa',
    name: 'KAFA',
    kind: ItemKind.counter,
    price: 200,
    opening: 1000,
    received: 0,
    closing: closing,
    portion: 20,
  );

  test('kafa se naplaćuje po porciji, a ne po gramu', () {
    final l = kafa(closing: 0);
    expect(l.consumed, 50);
    expect(l.amount, 50 * 200);
  });

  test('višak manji od jedne porcije je i dalje anomalija', () {
    final l = kafa(closing: 1010);
    expect(l.consumed, 0);
    expect(l.hasAnomaly, isTrue);
    expect(kafa(closing: 1000).hasAnomaly, isFalse);
  });
}
