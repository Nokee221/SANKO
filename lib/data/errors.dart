/// Greška koju korisnik treba vidjeti; poruka je već na bosanskom.
class SankoException implements Exception {
  SankoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Server nije dostupan; unos se nastavlja lokalno i šalje kasnije.
class OfflineException implements Exception {
  const OfflineException();
}

/// Server je odbio slanje smjene iz razloga koji telefon mora sam riješiti.
enum ShiftConflict {
  /// Smjenu je zaključio gazda; važi stanje sa servera.
  closedByAdmin('SK001'),

  /// Smjenu sada vodi drugi telefon istog radnika.
  takenOver('SK002'),

  /// Pri zaključenju fali stanje za artikal koji telefon još nema.
  missingCounts('SK003');

  const ShiftConflict(this.code);

  /// Kod greške sa servera.
  final String code;

  static ShiftConflict? fromCode(String? code) =>
      values.where((c) => c.code == code).firstOrNull;
}

class ShiftConflictException extends SankoException {
  ShiftConflictException(this.conflict, super.message);

  final ShiftConflict conflict;
}

/// Poziv nije stigao do servera ili se odgovor izgubio; na serveru je možda ipak upisan.
class NoConnectionException extends SankoException {
  NoConnectionException(super.message);
}
