import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/errors.dart';
import '../sync/supabase_errors.dart';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Pretplata ističe "uskoro" kad je do isteka ostalo ovoliko dana ili manje.
const expiringSoonDays = 7;

enum SubscriptionStatus { active, expiringSoon, expired }

class VendorVenue {
  const VendorVenue({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.name,
    required this.code,
    required this.paidUntil,
    required this.ownerEmails,
    required this.workers,
    required this.lastShiftAt,
    required this.shifts30,
  });

  factory VendorVenue.fromJson(Map<String, dynamic> j) => VendorVenue(
    id: j['id'] as String,
    orgId: j['org_id'] as String,
    orgName: j['org_name'] as String,
    name: j['name'] as String,
    code: j['code'] as String,
    paidUntil: DateTime.parse(j['paid_until'] as String),
    ownerEmails: (j['owner_emails'] as List).cast<String>(),
    workers: j['workers'] as int,
    lastShiftAt: j['last_shift_at'] == null
        ? null
        : DateTime.parse(j['last_shift_at'] as String).toLocal(),
    shifts30: j['shifts_30d'] as int,
  );

  final String id;
  final String orgId;
  final String orgName;
  final String name;

  /// Kod za telefone konobara.
  final String code;

  /// Zadnji plaćeni dan.
  final DateTime paidUntil;
  final List<String> ownerEmails;
  final int workers;
  final DateTime? lastShiftAt;

  /// Broj smjena u zadnjih 30 dana; pokazuje koliko se aplikacija stvarno koristi.
  final int shifts30;

  /// Dana do isteka; negativno kad je istekla.
  int daysLeft([DateTime? today]) =>
      paidUntil.difference(today ?? _today()).inDays;

  SubscriptionStatus status([DateTime? today]) {
    final left = daysLeft(today);
    if (left < 0) return SubscriptionStatus.expired;
    if (left <= expiringSoonDays) return SubscriptionStatus.expiringSoon;
    return SubscriptionStatus.active;
  }
}

class VendorOverview {
  const VendorOverview({required this.monthlyPrice, required this.venues});

  /// Mjesečna cijena po lokalu, u feninzima.
  final int monthlyPrice;
  final List<VendorVenue> venues;
}

class VendorPayment {
  const VendorPayment({
    required this.orgName,
    required this.venueName,
    required this.amount,
    required this.months,
    required this.paidUntilAfter,
    required this.note,
    required this.createdAt,
  });

  factory VendorPayment.fromJson(Map<String, dynamic> j) => VendorPayment(
    orgName: j['org_name'] as String,
    venueName: j['venue_name'] as String,
    amount: j['amount'] as int,
    months: j['months'] as int,
    paidUntilAfter: DateTime.parse(j['paid_until_after'] as String),
    note: j['note'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  final String orgName;
  final String venueName;

  /// Iznos u feninzima; 0 za ručne izmjene datuma.
  final int amount;
  final int months;
  final DateTime paidUntilAfter;
  final String? note;
  final DateTime createdAt;
}

/// Sve što panel prodavca radi nad serverom. Javlja promjene kao [Listenable].
abstract class VendorApi extends ChangeNotifier {
  Future<VendorOverview> overview();
  Future<List<VendorPayment>> payments();

  /// Produžava za cijele mjesece i zapisuje uplatu; vraća novi datum.
  Future<DateTime> extend(
    String venueId,
    int months,
    int amount, {
    String? note,
  });
  Future<void> setPaidUntil(String venueId, DateTime date, {String? note});

  /// Novi lokal postojeće firme; vraća kod za telefone.
  Future<String> addVenue(String orgId, String name, DateTime paidUntil);

  /// Novi kupac sa nalogom gazde; vraća kod lokala.
  Future<String> createCustomer({
    required String orgName,
    required String venueName,
    required String email,
    required String password,
    required DateTime paidUntil,
    required int amount,
    String? note,
  });
  Future<void> setPrice(int price);
}

class SupabaseVendorApi extends VendorApi {
  SupabaseVendorApi(this._client);

  final SupabaseClient _client;

  Future<T> _call<T>(Future<T> Function() call) async {
    try {
      return await supabaseCall(call);
    } on OfflineException {
      throw SankoException('Nema veze sa serverom. Provjerite internet.');
    }
  }

  @override
  Future<VendorOverview> overview() => _call(() async {
    final r = await _client.rpc('vendor_overview') as Map<String, dynamic>;
    return VendorOverview(
      monthlyPrice: r['monthly_price'] as int,
      venues: [
        for (final v in r['venues'] as List)
          VendorVenue.fromJson(v as Map<String, dynamic>),
      ],
    );
  });

  @override
  Future<List<VendorPayment>> payments() => _call(() async {
    final rows = await _client.rpc('vendor_payments') as List;
    return [
      for (final r in rows) VendorPayment.fromJson(r as Map<String, dynamic>),
    ];
  });

  @override
  Future<DateTime> extend(
    String venueId,
    int months,
    int amount, {
    String? note,
  }) async {
    final date = await _call(
      () => _client.rpc(
        'vendor_extend',
        params: {
          'p_venue_id': venueId,
          'p_months': months,
          'p_amount': amount,
          'p_note': note,
        },
      ),
    );
    notifyListeners();
    return DateTime.parse(date as String);
  }

  @override
  Future<void> setPaidUntil(
    String venueId,
    DateTime date, {
    String? note,
  }) async {
    await _call(
      () => _client.rpc(
        'vendor_set_paid_until',
        params: {
          'p_venue_id': venueId,
          'p_date': _dateKey(date),
          'p_note': note,
        },
      ),
    );
    notifyListeners();
  }

  @override
  Future<String> addVenue(String orgId, String name, DateTime paidUntil) async {
    final code = await _call(
      () => _client.rpc(
        'vendor_add_venue',
        params: {
          'p_org_id': orgId,
          'p_venue_name': name,
          'p_paid_until': _dateKey(paidUntil),
        },
      ),
    );
    notifyListeners();
    return code as String;
  }

  @override
  Future<String> createCustomer({
    required String orgName,
    required String venueName,
    required String email,
    required String password,
    required DateTime paidUntil,
    required int amount,
    String? note,
  }) async {
    try {
      final response = await _call(
        () => _client.functions.invoke(
          'create-owner',
          body: {
            'org_name': orgName,
            'venue_name': venueName,
            'email': email,
            'password': password,
            'paid_until': _dateKey(paidUntil),
            'amount': amount,
            'note': note,
          },
        ),
      );
      final data = response.data;
      final code = data is Map ? data['code'] : null;
      if (code is! String) {
        throw SankoException(
          'Server je odgovorio, ali bez koda lokala. Odgovor: $data',
        );
      }
      notifyListeners();
      return code;
    } on FunctionException catch (e) {
      final details = e.details;
      throw SankoException(
        details is Map && details['error'] is String
            ? details['error'] as String
            : e.status == 404
            ? 'Serverska funkcija create-owner nije postavljena u Supabaseu.'
            : 'Kupac nije otvoren (greška ${e.status}): $details',
      );
    }
  }

  @override
  Future<void> setPrice(int price) async {
    await _call(
      () => _client.rpc('vendor_set_price', params: {'p_price': price}),
    );
    notifyListeners();
  }
}
