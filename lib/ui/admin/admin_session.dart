import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/errors.dart';
import '../../sync/supabase_admin_data.dart';
import '../../sync/supabase_errors.dart';
import '../../vendor/vendor_api.dart';

class AdminVenue {
  const AdminVenue({
    required this.id,
    required this.name,
    required this.code,
    required this.paidUntil,
  });

  final String id;
  final String name;

  /// Kod koji konobari ukucaju na telefonu.
  final String code;

  /// Zadnji plaćeni dan.
  final DateTime paidUntil;
}

/// Prijava gazde i lokal koji trenutno gleda.
class AdminSession extends ChangeNotifier {
  AdminSession(this._client) {
    _authSub = _client.auth.onAuthStateChange.listen((_) => _load());
  }

  final SupabaseClient _client;
  late final StreamSubscription<AuthState> _authSub;

  bool loading = true;
  String? error;
  List<AdminVenue> venues = const [];
  AdminVenue? venue;
  SupabaseAdminData? data;

  /// Prijavljeni korisnik je superadmin (prodavac). Superadmin je poseban nalog
  /// i vidi samo panel za kafiće i pretplate, nikad panel gazde.
  bool isVendor = false;
  late final VendorApi vendorApi = SupabaseVendorApi(_client);

  /// Nova lozinka prijavljenog korisnika, npr. umjesto privremene.
  Future<void> changePassword(String password) async {
    if (password.length < 8) {
      throw SankoException('Lozinka mora imati bar 8 znakova.');
    }
    try {
      await supabaseCall(
        () => _client.auth.updateUser(UserAttributes(password: password)),
      );
    } on OfflineException {
      throw SankoException('Nema veze sa serverom. Provjerite internet.');
    }
  }

  bool get signedIn => _client.auth.currentSession != null;
  String? get email => _client.auth.currentUser?.email;

  @override
  void dispose() {
    _authSub.cancel();
    data?.dispose();
    super.dispose();
  }

  Future<void> signIn(String email, String password) async {
    try {
      await supabaseCall(
        () => _client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );
    } on OfflineException {
      throw SankoException('Nema veze sa serverom. Provjerite internet.');
    } on SankoException {
      throw SankoException('Pogrešan e-mail ili lozinka.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  void select(AdminVenue selected) {
    if (selected.id == venue?.id) return;
    data?.dispose();
    venue = selected;
    data = SupabaseAdminData(_client, selected.id);
    notifyListeners();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    if (!signedIn) {
      data?.dispose();
      data = null;
      venue = null;
      venues = const [];
      isVendor = false;
      loading = false;
      error = null;
      notifyListeners();
      return;
    }
    try {
      // Starija baza bez panela prodavca: korisnik je samo gazda.
      try {
        isVendor =
            await supabaseCall(() => _client.rpc('vendor_whoami')) == true;
      } on SankoException {
        isVendor = false;
      }
      final rows = await supabaseCall(
        () => _client
            .from('venues')
            .select('id, name, code, paid_until')
            .order('name'),
      );
      venues = [
        for (final r in rows)
          AdminVenue(
            id: r['id'] as String,
            name: r['name'] as String,
            code: r['code'] as String,
            paidUntil: DateTime.parse(r['paid_until'] as String),
          ),
      ];
      error = null;
      final current = venues.where((v) => v.id == venue?.id).firstOrNull;
      if (current != null) {
        venue = current;
      } else if (venues.isNotEmpty) {
        data?.dispose();
        venue = venues.first;
        data = SupabaseAdminData(_client, venue!.id);
      }
    } on OfflineException {
      error = 'Nema veze sa serverom. Provjerite internet.';
    } on SankoException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }
}
