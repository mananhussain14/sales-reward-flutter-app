import 'dart:async';

import 'package:sale_reward/features/auth/domain/entities/lifecycle_access_state.dart';
import 'package:sale_reward/features/auth/domain/repositories/lifecycle_access_repository.dart';

/// A [LifecycleAccessRepository] that answers on command.
///
/// The real repository is contractually non-throwing, so this fake does not
/// offer a "throw" mode by default — a test that wants to prove exception
/// collapsing exercises `SupabaseLifecycleAccessRepository` over a throwing
/// invoker instead, which is where that behaviour actually lives.
/// [throwOnRead] exists only for the one boundary case worth proving at this
/// seam: that a repository which breaks its contract cannot take the page down.
class FakeLifecycleAccessRepository implements LifecycleAccessRepository {
  /// The answer every read produces. Defaults to unavailable, which renders the
  /// ordinary access-denied card — so a test that never opts in sees exactly
  /// today's behaviour.
  LifecycleAccessResult result = const LifecycleAccessUnavailable();

  int callCount = 0;

  /// When true, every `read()` stays pending until [complete] is called — so
  /// "a result arriving after the page unmounted", "a subject change mid-flight"
  /// and "two mounts in sequence" are deterministic rather than a sleep-and-hope.
  bool manual = false;

  /// When true, `read()` throws instead of answering. Deliberately off by
  /// default: the production repository never throws.
  bool throwOnRead = false;

  final List<Completer<LifecycleAccessResult>> _pending =
      <Completer<LifecycleAccessResult>>[];

  int get pendingCount => _pending.length;

  /// Completes the oldest pending read, FIFO — so a test can answer a newer
  /// request before an older one.
  void complete([LifecycleAccessResult? override]) {
    _pending.removeAt(0).complete(override ?? result);
  }

  /// Convenience for the common case.
  void resolveWith(LifecycleAccessState state) {
    result = LifecycleAccessResolved(state);
  }

  @override
  Future<LifecycleAccessResult> read() async {
    callCount++;
    if (throwOnRead) {
      throw StateError('fake transport failure');
    }
    if (manual) {
      final Completer<LifecycleAccessResult> completer =
          Completer<LifecycleAccessResult>();
      _pending.add(completer);
      return completer.future;
    }
    return result;
  }
}
