import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/errors.dart';

/// Izvršava poziv prema Supabaseu i prevodi greške: odbijanje servera postaje
/// [SankoException] sa porukom servera, a nedostupan server [OfflineException].
Future<T> supabaseCall<T>(Future<T> Function() call) async {
  try {
    return await call().timeout(const Duration(seconds: 15));
  } on PostgrestException catch (e) {
    throw SankoException(e.message);
  } on AuthRetryableFetchException {
    throw const OfflineException();
  } on AuthException catch (e) {
    throw SankoException(e.message);
  } on SankoException {
    rethrow;
  } on FunctionException {
    // Serverska funkcija je odgovorila greškom; poruku čita onaj ko je zvao.
    rethrow;
  } catch (_) {
    // SocketException, ClientException, TimeoutException i slično.
    throw const OfflineException();
  }
}
