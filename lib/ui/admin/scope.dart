import 'package:flutter/material.dart';

import '../../data/admin_data.dart';
import '../common.dart';

/// Daje podatke odabranog lokala admin panelu i ponovo gradi zavisne widgete kad se promijene.
class AdminScope extends InheritedNotifier<AdminData> {
  const AdminScope({super.key, required AdminData data, required super.child})
    : super(notifier: data);

  static AdminData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminScope>()!.notifier!;
}

/// Učitava podatke odabranog lokala.
class AdminLoader<T> extends ScopedLoader<AdminData, T> {
  const AdminLoader({super.key, required super.load, required super.builder});

  @override
  AdminData sourceOf(BuildContext context) => AdminScope.of(context);
}
