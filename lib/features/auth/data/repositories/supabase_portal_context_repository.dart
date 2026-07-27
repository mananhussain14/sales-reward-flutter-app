import 'dart:async';

import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/portal_context.dart';
import '../../domain/repositories/portal_context_repository.dart';
import '../datasources/portal_context_data_source.dart';
import '../models/portal_context_parser.dart';

/// How long the portal-context RPC may take before the resolution is abandoned.
///
/// This is the gate between a signed-in user and their shell, so it is the one
/// call whose stalling is indistinguishable from a hung app. Twenty seconds is
/// far beyond the round trip this RPC actually needs and well short of a user
/// concluding the app is broken.
const Duration portalContextTimeout = Duration(seconds: 20);

/// The real [PortalContextRepository], backed by
/// `public.get_my_portal_context()`.
///
/// It does exactly three things, in order: call the RPC, parse the body, and
/// classify the answer. It reproduces **no** backend authorization logic — there
/// is no join over profiles, memberships, roles or permissions here, no
/// precedence rule, and no permission check. Every one of those decisions was
/// made in SQL by resolvers this class cannot see and does not duplicate.
///
/// ## Denial versus failure
///
/// The single most important behaviour in this file:
///
/// * `portal_kind: NONE` → [PortalContextDenied]. A decision. Send the user to
///   access-denied; a retry would return the same answer forever.
/// * a thrown exception, or a body this build cannot parse →
///   [PortalContextFailed]. Operational. Keep the session and offer a retry.
///
/// A malformed body is deliberately a *failure* rather than a denial. The
/// backend refusing you and the backend answering incomprehensibly are different
/// events, and only one of them is worth retrying.
final class SupabasePortalContextRepository implements PortalContextRepository {
  const SupabasePortalContextRepository(
    this._dataSource, {
    Duration timeout = portalContextTimeout,
  }) : _timeout = timeout;

  final PortalContextDataSource _dataSource;

  /// Injectable so a test can prove the timeout branch without waiting for it.
  final Duration _timeout;

  @override
  Future<PortalContextResult> resolve() async {
    final Object? raw;
    try {
      // Bounded on purpose. `SessionBloc` emits `SessionResolving` and then
      // waits for this future, and the router holds the splash for as long as
      // the session is indeterminate — so a call that never settles is not a
      // slow login, it is a permanent loading screen with no error and no
      // retry. A timeout converts that into an ordinary failure the user can
      // act on.
      raw = await _dataSource.fetch().timeout(_timeout);
    } on Object catch (error) {
      // Never surfaces the backend's own text: mapSupabaseError discriminates
      // on SQLSTATE and returns a discriminant, never a message.
      return PortalContextFailed(mapSupabaseError(error));
    }

    final PortalContext context;
    try {
      context = PortalContextParser.parse(raw);
    } on PortalContextFormatException {
      // Unreadable, not refused. Fail closed and let the user retry.
      return const PortalContextFailed(UnavailableFailure());
    }

    return context.isDenied
        ? PortalContextDenied(context)
        : PortalContextResolved(context);
  }
}
