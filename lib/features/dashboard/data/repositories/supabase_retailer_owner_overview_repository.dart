import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../../core/errors/sql_state.dart';
import '../../domain/repositories/retailer_owner_overview_repository.dart';
import '../datasources/retailer_owner_overview_rpc_data_source.dart';
import '../models/retailer_owner_overview_parser.dart';

/// How long the overview read may take before it is abandoned.
///
/// This is the first thing a Retailer Owner sees after signing in, so a call
/// that never settles is not a slow screen — it is a permanent skeleton with no
/// error and no retry. Twenty seconds is far beyond the round trip this RPC
/// needs (one indexed resolver and two counting subqueries) and well short of a
/// user concluding the app is broken.
///
/// Injectable on the repository so a test can prove the timeout branch without
/// waiting for it.
const Duration retailerOwnerOverviewTimeout = Duration(seconds: 20);

/// The real [RetailerOwnerOverviewRepository].
///
/// The read does exactly three things, in order: call the RPC, parse the body,
/// classify the answer. Each is somebody else's code — the data source, the
/// parser, and [classifyRetailerOverviewError] — so this class contains no
/// branching of its own beyond "did it throw?".
///
/// ## It reproduces no backend authorization logic
///
/// There is no Retailer organization id here, no membership lookup, no role
/// check, no permission check and no tenant predicate. Whether this caller may
/// read the overview is decided in SQL by
/// `resolve_retailer_owner_organization('RETAILER_PORTAL_READ')`, which requires
/// an ACTIVE profile, an ACTIVE membership, an ACTIVE `RETAILER` organization,
/// an ACTIVE `RETAILER_OWNER` role holding that permission, and **exactly one**
/// qualifying organization. Restating any of it here would create a second
/// definition free to drift, and only one of the two could be right.
///
/// ## It reproduces no counting logic either
///
/// Neither shop count is derived, filtered or combined on this side of the wire.
/// Both arrive already computed against the resolved organization id — which is
/// what keeps the client from ever needing a shop id in order to count shops,
/// and what keeps the figures identical to the ones the web portal shows.
final class SupabaseRetailerOwnerOverviewRepository
    implements RetailerOwnerOverviewRepository {
  const SupabaseRetailerOwnerOverviewRepository({
    required RetailerOwnerOverviewRpcDataSource rpc,
    Duration timeout = retailerOwnerOverviewTimeout,
  }) : _rpc = rpc,
       _timeout = timeout;

  final RetailerOwnerOverviewRpcDataSource _rpc;
  final Duration _timeout;

  /// Call → parse → classify, with the three outcomes kept apart.
  ///
  /// * A **thrown** call is classified by [classifyRetailerOverviewError], which
  ///   discriminates on exception type and SQLSTATE and never on message text.
  /// * A **well-formed empty** body is [RetailerOverviewIneligible] — a success,
  ///   not a failure, and never retried into a different answer.
  /// * An **unparseable** body is [RetailerOverviewProblem.malformed]. Unreadable
  ///   is not ineligible and it is certainly not an overview of zeros:
  ///   fabricating one would tell an Owner they have no shops when the response
  ///   simply could not be understood.
  @override
  Future<RetailerOverviewResult> overview() async {
    final Object? raw;
    try {
      raw = await _rpc.fetchOverview().timeout(_timeout);
    } on Object catch (error) {
      return RetailerOverviewFailed(classifyRetailerOverviewError(error));
    }

    try {
      return switch (RetailerOwnerOverviewParser.parse(raw)) {
        ParsedRetailerOverviewRow(:final overview) => RetailerOverviewLoaded(
          overview,
        ),
        ParsedRetailerOverviewEmpty() => const RetailerOverviewIneligible(),
      };
    } on RetailerOwnerOverviewFormatException {
      // The exception's own `reason` is developer-facing and stays here. Only
      // the discriminant travels onward.
      return const RetailerOverviewFailed(RetailerOverviewProblem.malformed);
    }
  }
}

/// Classifies a thrown overview read.
///
/// ## Discrimination is by type and machine code only
///
/// Nothing here reads `error.message`, for display or for branching. Postgres
/// messages name tables, columns, functions and policies; GoTrue messages are
/// prose that changes between releases and can carry account detail. The backend
/// contract is explicit that message text is not an API, so neither is read and
/// neither travels onward — only a [RetailerOverviewProblem] does.
///
/// ## Why transport is split from "unexpected"
///
/// `mapSupabaseError` folds every unrecognised throw into `UnavailableFailure`,
/// whose shared copy is *"Check your connection and try again."* On this screen
/// that would report a programming error, an unreadable response and a genuine
/// outage with the same sentence. So the two connection-shaped failures are
/// identified positively, and everything unidentified degrades to
/// [RetailerOverviewProblem.unexpected] rather than borrowing their message.
///
/// `http.ClientException` is the single check that covers both platforms:
/// `postgrest` propagates the transport exception unchanged, and `package:http`
/// wraps a VM `SocketException` in `_ClientSocketException`, which **extends**
/// `ClientException`. Matching the base type therefore catches a refused socket,
/// an unresolved host and a browser fetch refusal alike — without importing
/// `dart:io`, which does not exist on Flutter web.
///
/// ## Fail closed
///
/// No branch returns a success-shaped value. An unrecognised throw is a failure,
/// never ineligibility and never an empty overview.
RetailerOverviewProblem classifyRetailerOverviewError(Object error) {
  if (error is TimeoutException) {
    return RetailerOverviewProblem.timeout;
  }

  // Checked before PostgrestException: the transport exception is what the SDK
  // propagates when the request never arrived, and it carries no SQLSTATE to
  // classify.
  if (error is http.ClientException) {
    return RetailerOverviewProblem.network;
  }

  if (error is sb.PostgrestException) {
    return switch (error.code) {
      SqlState.insufficientPrivilege => RetailerOverviewProblem.denied,
      // A recognised SQLSTATE this RPC has no business raising, or none at all.
      // The read is `STABLE` and touches no constraint, so a duplicate, a check
      // violation or a prerequisite-state error would mean the deployed
      // function is not the one this build expects.
      _ => RetailerOverviewProblem.unexpected,
    };
  }

  if (error is sb.AuthException) {
    // The session is absent, expired or rejected. Deliberately not bound to a
    // message: auth exceptions can carry token material.
    return RetailerOverviewProblem.signedOut;
  }

  return RetailerOverviewProblem.unexpected;
}
