import 'package:flutter/material.dart';

import 'app.dart';
import 'data/repository.dart';
import 'sync/waiter_sync.dart';
import 'ui/waiter/pin_screen.dart';
import 'ui/waiter/scope.dart';
import 'ui/waiter/venue_code_screen.dart';

/// Aplikacija za telefon konobara: unos ide u lokalnu bazu i šalje se na server kad ima mreže.
class WaiterApp extends StatelessWidget {
  const WaiterApp({super.key, required this.repo, required this.sync});

  final Repository repo;
  final WaiterSync sync;

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      repo: repo,
      child: SyncScope(
        sync: sync,
        child: SankoMaterialApp(
          home: Builder(
            builder: (context) => SyncScope.of(context).venueCode == null
                ? const VenueCodeScreen()
                : const PinScreen(),
          ),
        ),
      ),
    );
  }
}
