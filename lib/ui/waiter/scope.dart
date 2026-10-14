import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../sync/waiter_sync.dart';
import '../common.dart';

/// Daje lokalnu bazu telefona stablu i ponovo gradi zavisne widgete kad se podaci promijene.
class RepoScope extends InheritedNotifier<Repository> {
  const RepoScope({super.key, required Repository repo, required super.child})
    : super(notifier: repo);

  static Repository of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepoScope>()!.notifier!;
}

/// Daje vezu sa serverom stablu; zavisni widgeti prate stanje prijave i slanja.
class SyncScope extends InheritedNotifier<WaiterSync> {
  const SyncScope({super.key, required WaiterSync sync, required super.child})
    : super(notifier: sync);

  static WaiterSync of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}

/// Učitava podatke iz lokalne baze telefona.
class Loader<T> extends ScopedLoader<Repository, T> {
  const Loader({super.key, required super.load, required super.builder});

  @override
  Repository sourceOf(BuildContext context) => RepoScope.of(context);
}

/// Osvježava sa servera i kratko javi ishod.
Future<void> refreshWithMessage(
  BuildContext context, {
  bool quiet = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final error = await SyncScope.of(context).refresh(images: true);
  if (quiet && error == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(error ?? 'Artikli su osvježeni'),
      ),
    );
}
