import '../data/models.dart';
import '../data/orders.dart';
import 'remote_shift.dart';

/// Rezultat prijave konobara na serveru.
class LoginResult {
  const LoginResult.ok({
    required String this.workerId,
    required String this.workerName,
    required String this.venueName,
    this.role = WorkerRole.konobar,
  }) : error = null;

  const LoginResult.rejected(String this.error)
    : workerId = null,
      workerName = null,
      venueName = null,
      role = WorkerRole.konobar;

  /// Poruka servera kad prijava nije prihvaćena; null kad jeste.
  final String? error;
  final String? workerId;
  final String? workerName;
  final String? venueName;
  final WorkerRole role;

  bool get ok => error == null;
}

/// Server kako ga vidi telefon konobara. Sve metode bacaju OfflineException
/// kad server nije dostupan i SankoException kad server odbije zahtjev.
abstract interface class WaiterBackend {
  Future<LoginResult> login(String venueCode, String pin);

  /// Otvara smjenu za prijavljenog radnika (ili vraća njegovu već otvorenu) sa cijelim stanjem.
  Future<RemoteShift> startShift(String newShiftId);

  Future<RemoteShift> fetchShift(String shiftId);

  /// Slike iz kataloga po oznakama.
  Future<List<CatalogImage>> fetchImages(List<String> ids);

  /// Šalje cijelo stanje smjene; poziv se može ponavljati bez štete.
  Future<void> pushShift(Map<String, Object?> payload);

  /// Artikli i stolovi lokala za kucanje narudžbe.
  Future<Menu> fetchMenu();

  /// Šalje narudžbu na šank; ponovljeno slanje iste narudžbe je ne udvostručuje.
  Future<Order> placeOrder(NewOrder order);

  /// Sa [mine] narudžbe prijavljenog konobara od danas, najnovije prve;
  /// inače narudžbe lokala koje šank još nije završio, najstarije prve.
  Future<List<Order>> fetchOrders({required bool mine});

  /// Šank označava narudžbu kao gotovu, ili je vraća ako je povučena greškom.
  Future<void> setOrderDone(String orderId, {required bool done});
}
