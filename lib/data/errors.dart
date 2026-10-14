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
