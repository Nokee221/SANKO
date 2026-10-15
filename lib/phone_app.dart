import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_app.dart';
import 'app.dart';
import 'config.dart';
import 'data/db.dart';
import 'data/repository.dart';
import 'sync/supabase_waiter_backend.dart';
import 'sync/waiter_sync.dart';
import 'ui/admin/admin_session.dart';
import 'ui/role_screen.dart';
import 'waiter_app.dart';

const _roleKey = 'phone_role';

/// Aplikacija na telefonu: konobar unosi smjenu, a gazda na istoj aplikaciji
/// vidi sve što i na računaru. Izbor se pamti na telefonu.
Future<void> runPhoneApp() async {
  // Ekrani telefona su pravljeni za uspravan položaj.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final client = Supabase.instance.client;
  final repo = Repository(await openAppDatabase());
  final sync = WaiterSync(repo, SupabaseWaiterBackend(client, repo));
  await sync.init();
  final stored = await repo.meta(_roleKey);
  runApp(
    PhoneApp(
      repo: repo,
      sync: sync,
      session: AdminSession(client),
      role: stored == null ? null : PhoneRole.values.byName(stored),
    ),
  );
}

class PhoneApp extends StatefulWidget {
  const PhoneApp({
    super.key,
    required this.repo,
    required this.sync,
    required this.session,
    this.role,
  });

  final Repository repo;
  final WaiterSync sync;
  final AdminSession session;

  /// Zapamćen izbor; null pri prvom pokretanju.
  final PhoneRole? role;

  @override
  State<PhoneApp> createState() => _PhoneAppState();
}

class _PhoneAppState extends State<PhoneApp> {
  // Telefon na kojem je konobar već radio, prije ovog izbora, ostaje telefon konobara.
  late PhoneRole? _role =
      widget.role ??
      (widget.sync.venueCode != null
          ? PhoneRole.waiter
          : widget.session.signedIn
          ? PhoneRole.owner
          : null);

  Future<void> _set(PhoneRole role) async {
    setState(() => _role = role);
    await widget.repo.setMeta(_roleKey, role.name);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_role) {
      null => SankoMaterialApp(home: RoleScreen(onPick: _set)),
      PhoneRole.waiter => PhoneRoleScope(
        switchTo: _set,
        child: WaiterApp(repo: widget.repo, sync: widget.sync),
      ),
      PhoneRole.owner => AdminApp(
        session: widget.session,
        mobile: true,
        onSwitchToWaiter: () => _set(PhoneRole.waiter),
      ),
    };
  }
}
