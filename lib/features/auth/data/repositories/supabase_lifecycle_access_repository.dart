import 'dart:async';

import '../../domain/entities/lifecycle_access_state.dart';
import '../../domain/repositories/lifecycle_access_repository.dart';
import '../datasources/lifecycle_access_rpc_data_source.dart';
import '../models/lifecycle_access_parser.dart';

/// How long the diagnostic may take before it is abandoned as unavailable.
///
/// Matched to `portalContextTimeout`, because the two calls sit on the same
/// transport and a user who has already been refused should not wait longer for
/// an explanation than they waited for the refusal. An expiry is not a special
/// case here — it is one more way of not knowing, and produces the same
/// [LifecycleAccessUnavailable] as every other.
const Duration lifecycleAccessTimeout = Duration(seconds: 20);

/// The real [LifecycleAccessRepository], backed by
/// `public.get_my_lifecycle_access_state()`.
///
/// It does exactly two things: call the RPC once, and parse the body. It
/// reproduces **no** backend logic — there is no join over profiles,
/// memberships, roles or organizations here, no precedence rule, and no
/// permission check. Every one of those decisions was made in SQL by a function
/// this class cannot see and does not duplicate.
///
/// ## One try, one catch, and the error is deliberately not bound
///
/// The `catch` below writes `catch (_)`, discarding the error object rather than
/// naming it. That is the enforcement mechanism, not a style choice: with no
/// identifier in scope there is nothing to inspect, nothing to log, nothing to
/// branch on and nothing to accidentally surface. A reviewer does not have to
/// verify that `error.message` is unused — it is unreachable.
///
/// There is deliberately **no SQLSTATE branching** and no call to the shared
/// `mapSupabaseError`. That mapper turns `42501` into `DeniedFailure`, which
/// would recreate exactly the unauthenticated-versus-transport distinction this
/// feature exists to collapse: a caller able to tell those apart holds a probe,
/// and a page that has already refused access gains nothing from the difference.
///
/// ## No retry, no fallback, no second opinion
///
/// One `fetch()` per [read]. There is no retry loop, no fallback query, no
/// direct table read and no second RPC. The answer describes a state a Retailer
/// Owner can change at any moment, so a retry would not be more accurate — only
/// later — and the page already offers the user a deliberate, canonical way to
/// ask again.
final class SupabaseLifecycleAccessRepository
    implements LifecycleAccessRepository {
  const SupabaseLifecycleAccessRepository(
    this._dataSource, {
    Duration timeout = lifecycleAccessTimeout,
  }) : _timeout = timeout;

  final LifecycleAccessRpcDataSource _dataSource;

  /// Injectable so a test can prove the timeout branch without waiting for it.
  final Duration _timeout;

  @override
  Future<LifecycleAccessResult> read() async {
    try {
      final Object? raw = await _dataSource.fetch().timeout(_timeout);
      final LifecycleAccessState state = LifecycleAccessParser.parse(raw);
      return LifecycleAccessResolved(state);
    } on Object catch (_) {
      // Every failure, identically: PostgrestException on any SQLSTATE
      // (42501 for an unauthenticated caller included), AuthException,
      // ClientException, TimeoutException, RpcFormatException from the parser,
      // and anything else at all.
      return const LifecycleAccessUnavailable();
    }
  }
}
