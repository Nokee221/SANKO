import 'package:flutter/foundation.dart';

import '../domain/obracun.dart';
import '../domain/report.dart';
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
    int? minQty,
    int? parQty,
  });

  /// Upisuje više artikala odjednom, redom iza postojećih; npr. uvoz iz Excela.
  Future<void> addItems(List<NewItem> items);
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
  /// za ostale artikle važi ono što je telefon već poslao. Uz [handover] se upisuje
  /// i kuhinja i predaja novca.
  Future<void> adminCloseShift(
    String shiftId,
    Map<String, int> counts, {
    Handover? handover,
  });

  /// Ispravlja kuhinju i predaju zaključene smjene; promjena se zapisuje.
  Future<void> setHandover(String shiftId, Handover handover, {String? note});

  /// Zbirovi zaključenih smjena od [from] do [to], uključivo, najstarije prve.
  Future<List<ShiftSummary>> shiftSummaries(DateTime from, DateTime to);

  /// Veza lokala sa Telegramom za obavještenja.
  Future<TelegramStatus> telegramStatus();

  /// Link koji gazda otvori u Telegramu da poveže razgovor sa lokalom.
  Future<String> telegramLink();

  /// Gasi obavještenja za sve povezane razgovore lokala.
  Future<void> telegramUnlink();

  /// Ponovo učitava prikaz, npr. na dugme "Osvježi".
  void refresh();
}
