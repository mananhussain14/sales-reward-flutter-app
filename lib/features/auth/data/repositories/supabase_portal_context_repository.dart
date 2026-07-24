import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../domain/entities/portal_context.dart';
import '../../domain/repositories/portal_context_repository.dart';
import '../datasources/portal_context_data_source.dart';
import '../models/portal_context_parser.dart';

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
  const SupabasePortalContextRepository(this._dataSource);

  final PortalContextDataSource _dataSource;

  @override
  Future<PortalContextResult> resolve() async {
    final Object? raw;
    try {
      raw = await _dataSource.fetch();
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
