import 'package:flutter/widgets.dart';

import 'design_store.dart';

/// Exposes the store to the tree and rebuilds dependents on every change —
/// the Flutter counterpart of the design's `useApp()` hook.
class FlvpStoreScope extends InheritedNotifier<FlvpDesignStore> {
  const FlvpStoreScope({
    super.key,
    required FlvpDesignStore store,
    required super.child,
  }) : super(notifier: store);

  static FlvpDesignStore of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FlvpStoreScope>()!
      .notifier!;

  /// Reads the store without subscribing (for callbacks).
  static FlvpDesignStore read(BuildContext context) => context
      .getInheritedWidgetOfExactType<FlvpStoreScope>()!
      .notifier!;
}
