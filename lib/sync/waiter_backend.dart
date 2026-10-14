import '../data/models.dart';
import 'remote_shift.dart';

/// Rezultat prijave konobara na serveru.
class LoginResult {
  const LoginResult.ok({
    required String this.workerId,
    required String this.workerName,
    required String this.venueName,
  }) : error = null;

  const LoginResult.rejected(String this.error)
    : workerId = null,
      workerName = null,
      venueName = null;

  /// Poruka servera kad prijava nije prihvaćena; null kad jeste.
  final String? error;
  final String? workerId;
  final String? workerName;
  final String? venueName;

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
}
