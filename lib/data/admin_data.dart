import 'package:flutter/foundation.dart';

import '../domain/obracun.dart';
import '../domain/stats.dart';
import 'models.dart';

/// Podaci jednog lokala kako ih vidi admin panel. Javlja promjene kao [Listenable].
abstract interface class AdminData implements Listenable {
  Future<List<Worker>> workers();
  Future<void> addWorker({required String name, required String pin});
  Future<void> removeWorker(String id);

  Future<List<Item>> items();

  /// Artikal je već bio u nekoj smjeni; njegovo početno stanje se više ne može mijenjati.
  Future<bool> itemHasHistory(String id);
  Future<void> addItem({
    required String name,
    required ItemKind kind,
    required int price,
    int initialQty,
    String? imageId,
  });
  Future<void> updateItem(Item item);
  Future<void> removeItem(String id);
  Future<void> seedDemoItems();

  /// Zajednički katalog slika iz kojeg gazda bira sliku artikla.
  Future<List<CatalogImage>> catalogImages();

  Future<List<Shift>> shiftsOn(DateTime day);
  Future<Obracun> obracunForShift(String shiftId);
  Future<List<Expense>> expenses(String shiftId);

  /// Utrošeno i primljeno po artiklu u zaključenim smjenama od [from] do [to], uključivo.
  Future<List<StatLine>> statLines(DateTime from, DateTime to);

  /// Ispravlja zaključenu smjenu; ispravljen ostatak postaje početno stanje sljedeće smjene.
  Future<void> correctShift(
    String shiftId,
    List<ItemCorrection> changes, {
    String? note,
  });

  /// Zapisi o ispravkama datih smjena, najstarije prvo.
  Future<List<ShiftCorrection>> corrections(List<String> shiftIds);

  /// Trenutna zaliha artikala koji se broje na komad.
  Future<List<StockLevel>> currentStock();

  /// Zaključuje smjenu umjesto konobara. [counts] je stanje po artiklu koje gazda unosi;
  /// za ostale artikle važi ono što je telefon već poslao.
  Future<void> adminCloseShift(String shiftId, Map<String, int> counts);

  /// Ponovo učitava prikaz, npr. na dugme "Osvježi".
  void refresh();
}
