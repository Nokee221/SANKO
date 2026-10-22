import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/orders.dart';
import '../data/repository.dart';
import 'waiter_backend.dart';

const _venueCodeKey = 'venue_code';
const _venueNameKey = 'venue_name';
const _sessionWorkerKey = 'session_worker_id';

/// Veza telefona sa serverom: prijava, početak smjene i slanje unosa.
/// Unos tokom smjene ide u lokalnu bazu; odavde se šalje čim ima mreže.
class WaiterSync extends ChangeNotifier {
  WaiterSync(this._repo, this._backend, {bool autoSync = true})
    : _autoSync = autoSync;

  final Repository _repo;
  final WaiterBackend _backend;
  final bool _autoSync;

  Timer? _debounce;
  Timer? _retry;
  bool _pushing = false;

  String? _venueCode;
  String? _venueName;
  String? _sessionWorkerId;
  bool _hasUnsent = false;
  String? _lastError;

  /// Kod lokala za koji je telefon podešen; null dok se ne unese.
  String? get venueCode => _venueCode;
  String? get venueName => _venueName;

  /// Ima unosa koji još nisu stigli na server.
  bool get hasUnsent => _hasUnsent;

  /// Zadnja greška kojom je server odbio slanje; null kad je sve u redu ili samo nema mreže.
  String? get lastError => _lastError;

  Future<void> init() async {
    _venueCode = await _repo.meta(_venueCodeKey);
    _venueName = await _repo.meta(_venueNameKey);
    _sessionWorkerId = await _repo.meta(_sessionWorkerKey);
    _hasUnsent = await _repo.hasUnsent();
    if (_autoSync) {
      _repo.addListener(_schedulePush);
      // Šalje unose i preuzima artikle koje je gazda u međuvremenu dodao.
      _retry = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
      unawaited(pushNow());
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _repo.removeListener(_schedulePush);
    _debounce?.cancel();
    _retry?.cancel();
    super.dispose();
  }

  Future<void> setVenueCode(String? code) async {
    _venueCode = code?.trim().toUpperCase();
    _venueName = null;
    await _repo.setMeta(_venueCodeKey, _venueCode);
    await _repo.setMeta(_venueNameKey, null);
    notifyListeners();
  }

  /// Prijava PIN-om. Sa mrežom odlučuje server; bez mreže prolazi samo radnik
  /// koji se na ovom telefonu već jednom uspješno prijavio.
  Future<Worker> login(String pin) async {
    final LoginResult result;
    try {
      result = await _backend.login(_venueCode!, pin);
    } on OfflineException {
      final cached = await _repo.workerByPin(pin);
      if (cached == null) {
        throw SankoException(
          'Nema interneta. Prva prijava na ovom telefonu traži internet.',
        );
      }
      return cached;
    }
    if (!result.ok) {
      await _repo.forgetPin(pin);
      throw SankoException(result.error!);
    }
    await _repo.cacheWorker(
      id: result.workerId!,
      name: result.workerName!,
      pin: pin,
      role: result.role,
    );
    _sessionWorkerId = result.workerId;
    _venueName = result.venueName;
    await _repo.setMeta(_sessionWorkerKey, _sessionWorkerId);
    await _repo.setMeta(_venueNameKey, _venueName);
    notifyListeners();
    unawaited(pushNow());
    _refreshing = refresh(images: true);
    return Worker(
      id: result.workerId!,
      name: result.workerName!,
      pin: pin,
      role: result.role,
    );
  }

  Future<void> _refreshing = Future.value();

  /// Osvježavanje otvorene smjene i slika koje je pokrenula zadnja prijava;
  /// prijava ga ne čeka, da konobar odmah uđe.
  Future<void> get pendingRefresh => _refreshing;

  /// Otvara smjenu na serveru i preuzima je na telefon. Traži internet, jer server
  /// garantuje jednu otvorenu smjenu po lokalu i daje stanje iz prethodne.
  Future<Shift> startShift(Worker worker) async {
    try {
      // Telefon je na serveru možda još prijavljen kao drugi radnik (prijava bez mreže).
      if (_sessionWorkerId != worker.id) await login(worker.pin);
      if (_sessionWorkerId != worker.id) throw const OfflineException();
      final remote = await _backend.startShift(const Uuid().v4());
      await _repo.importShift(remote);
      await _syncImages(refresh: true);
      return await _repo.shiftById(remote.id);
    } on OfflineException {
      throw SankoException('Za početak smjene je potreban internet.');
    }
  }

  /// Narudžbe idu odmah na šank, pa traže internet. Ako je telefon na serveru
  /// prijavljen kao drugi radnik (prijava bez mreže), prvo se ponovo prijavljuje.
  Future<T> _online<T>(
    Worker worker,
    String offlineMessage,
    Future<T> Function() call,
  ) async {
    try {
      if (_sessionWorkerId != worker.id) await login(worker.pin);
      if (_sessionWorkerId != worker.id) throw const OfflineException();
      return await call();
    } on OfflineException {
      throw SankoException(offlineMessage);
    }
  }

  /// Artikli i stolovi za kucanje, sa slikama artikala po oznaci slike.
  Future<(Menu, Map<String, Uint8List>)> menu(Worker worker) =>
      _online(worker, 'Nema interneta. Narudžbe traže internet.', () async {
        final menu = await _backend.fetchMenu();
        final ids = {
          for (final i in menu.items)
            if (i.imageId != null) i.imageId!,
        };
        var images = await _repo.imagesByIds(ids);
        final missing = ids.difference(images.keys.toSet()).toList();
        if (missing.isNotEmpty) {
          await _repo.saveImages(await _backend.fetchImages(missing));
          images = await _repo.imagesByIds(ids);
        }
        return (menu, images);
      });

  Future<Order> placeOrder(Worker worker, NewOrder order) => _online(
    worker,
    'Nema interneta. Narudžba nije poslana; pokušajte ponovo.',
    () => _backend.placeOrder(order),
  );

  Future<List<Order>> orders(Worker worker, {required bool mine}) => _online(
    worker,
    'Nema interneta. Narudžbe se ne mogu učitati.',
    () => _backend.fetchOrders(mine: mine),
  );

  Future<void> setOrderDone(
    Worker worker,
    String orderId, {
    required bool done,
  }) => _online(
    worker,
    'Nema interneta. Narudžba nije označena; pokušajte ponovo.',
    () => _backend.setOrderDone(orderId, done: done),
  );

  /// Preuzima slike artikala koje telefon još nema. Sa [refresh] ponovo preuzima
  /// sve, jer prodavac može zamijeniti sliku pod istim nazivom (npr. probnu pravom).
  Future<void> _syncImages({bool refresh = false}) async {
    final ids = refresh
        ? await _repo.usedImageIds()
        : await _repo.missingImageIds();
    if (ids.isEmpty) return;
    await _repo.saveImages(await _backend.fetchImages(ids));
  }

  /// Šalje neposlane unose i preuzima otvorenu smjenu sa servera: artikle koje je gazda
  /// dodao, ispravljena početna stanja i slike. Lokalni unosi ostaju netaknuti.
  /// Sa [images] ponovo preuzima i sve slike, ne samo one koje nedostaju.
  /// Vraća poruku za korisnika kad osvježavanje nije uspjelo, inače null.
  Future<String?> refresh({bool images = false}) async {
    final workerId = _sessionWorkerId;
    if (workerId == null) return null;
    await pushNow();
    try {
      final open = await _repo.openShift();
      if (open == null || open.workerId != workerId) return null;
      await _repo.importShift(await _backend.fetchShift(open.id));
      await _syncImages(refresh: images);
      return null;
    } on OfflineException {
      return 'Nema interneta. Artikli će se osvježiti kad se veza vrati.';
    } on SankoException catch (e) {
      return e.message;
    }
  }

  void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), pushNow);
    _refreshUnsent();
  }

  Future<void> _refreshUnsent() async {
    final unsent = await _repo.hasUnsent();
    if (unsent == _hasUnsent) return;
    _hasUnsent = unsent;
    notifyListeners();
  }

  /// Šalje sve neposlane smjene radnika za kojeg je telefon prijavljen na serveru.
  /// Bez mreže ne radi ništa; unosi ostaju označeni i šalju se sljedeći put.
  Future<void> pushNow() async {
    final workerId = _sessionWorkerId;
    if (_pushing || workerId == null) return;
    _pushing = true;
    try {
      final dirty = await _repo.dirtyShifts(workerId);
      for (final MapEntry(key: shiftId, value: revision) in dirty.entries) {
        final shift = await _repo.exportShift(shiftId);
        await _backend.pushShift(shift.toPayload());
        await _repo.markClean(shiftId, revision);
        // Gazda je možda usred smjene dodao artikal; preuzmi stavke koje nedostaju.
        if (shift.closedAt == null) {
          await _repo.importShift(await _backend.fetchShift(shiftId));
        }
      }
      await _syncImages();
      _lastError = null;
    } on OfflineException {
      // Nema mreže; pokušava se ponovo kasnije.
    } on SankoException catch (e) {
      _lastError = e.message;
    } finally {
      _pushing = false;
      _hasUnsent = await _repo.hasUnsent();
      notifyListeners();
    }
  }
}
