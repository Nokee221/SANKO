import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'remote_shift.dart';
import 'supabase_errors.dart';
import 'waiter_backend.dart';

const _deviceIdKey = 'device_id';
const _tokenKey = 'session_token';

/// Telefon nema Supabase nalog. Prijava kodom lokala i PIN-om vraća tajni token,
/// koji se čuva na telefonu i šalje uz svaki sljedeći poziv.
class SupabaseWaiterBackend implements WaiterBackend {
  SupabaseWaiterBackend(this._client, this._repo);

  final SupabaseClient _client;
  final Repository _repo;

  /// Slučajna oznaka ovog telefona, napravljena pri prvoj prijavi.
  Future<String> _deviceId() async {
    var id = await _repo.meta(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await _repo.setMeta(_deviceIdKey, id);
    }
    return id;
  }

  @override
  Future<LoginResult> login(String venueCode, String pin) =>
      supabaseCall(() async {
        final r =
            await _client.rpc(
                  'waiter_login',
                  params: {
                    'p_venue_code': venueCode,
                    'p_pin': pin,
                    'p_device_id': await _deviceId(),
                  },
                )
                as Map<String, dynamic>;
        if (r['ok'] != true) return LoginResult.rejected(r['error'] as String);
        await _repo.setMeta(_tokenKey, r['token'] as String);
        return LoginResult.ok(
          workerId: r['worker']['id'] as String,
          workerName: r['worker']['name'] as String,
          venueName: r['venue']['name'] as String,
        );
      });

  @override
  Future<RemoteShift> startShift(String newShiftId) => supabaseCall(() async {
    final shift = await _client.rpc(
      'start_shift',
      params: {
        'p_token': await _repo.meta(_tokenKey),
        'p_shift_id': newShiftId,
      },
    );
    return RemoteShift.fromJson(shift as Map<String, dynamic>);
  });

  @override
  Future<RemoteShift> fetchShift(String shiftId) => supabaseCall(() async {
    final shift = await _client.rpc(
      'fetch_shift',
      params: {'p_token': await _repo.meta(_tokenKey), 'p_shift_id': shiftId},
    );
    return RemoteShift.fromJson(shift as Map<String, dynamic>);
  });

  @override
  Future<List<CatalogImage>> fetchImages(List<String> ids) =>
      supabaseCall(() async {
        final rows = await _client.rpc(
          'fetch_images',
          params: {'p_token': await _repo.meta(_tokenKey), 'p_ids': ids},
        );
        return [
          for (final r in rows as List)
            CatalogImage(
              id: r['id'] as String,
              name: r['name'] as String,
              bytes: base64Decode(r['data'] as String),
            ),
        ];
      });

  @override
  Future<void> pushShift(Map<String, Object?> payload) => supabaseCall(
    () async => _client.rpc(
      'sync_shift',
      params: {'p_token': await _repo.meta(_tokenKey), 'p_shift': payload},
    ),
  );
}
