import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'sql_state.dart';

/// Why a Retailer portal read did not produce rows.
///
/// ## Why this exists rather than a bare `Failure`
///
/// The shared [Failure] union collapses every transport, serialization and
/// unrecognised backend fault into one `UnavailableFailure`, whose copy is
/// *"Check your connection and try again."* That is right for most screens and
/// wrong for the Retailer portal: "we could not reach the service", "the service
/// answered something this build cannot read" and "something in our own code
/// broke" would all be reported as a connection problem, sending a user to fix a
/// connection that is working.
///
/// ## One taxonomy for three features
///
/// Shops, Staff and Assigned Products share this rather than each declaring
/// their own. The codebase's own promotion rule — recorded on `ReadResult` —
/// is *"when a third feature needs one, that is the evidence to promote it."*
/// Three features need it, so it lives here.
///
/// The Retailer Owner Overview keeps its own `RetailerOverviewProblem`, which is
/// structurally identical. That is deliberate for this milestone: the Overview
/// shipped and was verified on a device in the previous one, and the instruction
/// was to preserve it. Consolidating the two is a mechanical follow-up, recorded
/// as a known limitation rather than done here.
///
/// ## What is deliberately absent
///
/// There is no member for "this Retailer is inactive" or "your membership is
/// suspended". The backend does not distinguish them: every Retailer resolver
/// either returns an organization or returns NULL, and the caller sees one
/// generic refusal or an empty set. Inventing a reason in Dart would fabricate a
/// distinction the database refused to make.
enum RetailerReadProblem {
  /// `42501`. The caller is signed in and refused.
  ///
  /// The Staff, Invitation and Product reads raise this explicitly when their
  /// resolver returns NULL. The **Shops** read does not — see
  /// `RetailerShopRepository` for why an unauthorized Shops caller receives an
  /// empty list instead, and why that is not represented as a denial.
  denied,

  /// There is no verified session. Not a refusal: the caller is not signed in
  /// rather than signed in and refused.
  signedOut,

  /// The response could not be understood — a wrong shape, a required field
  /// missing or null, or a value of the wrong type.
  ///
  /// Never rendered as an empty list. "This build could not read the answer" and
  /// "you have none of these" are opposite claims.
  malformed,

  /// The request never reached the backend: no route, no DNS answer, a refused
  /// TLS handshake, a blocked socket, a browser CORS refusal.
  ///
  /// One of only two members whose copy mentions the connection.
  network,

  /// The request was sent and nothing came back in time.
  timeout,

  /// Anything else — an unexpected SDK state or a programming error. Not a
  /// statement about the user's network.
  unexpected,
}

/// How long a Retailer portal read may take before it is abandoned.
///
/// These are the screens a Retailer Owner lives in, so a call that never settles
/// is not a slow list — it is a permanent skeleton with no error and no retry.
/// Twenty seconds is far beyond the round trip these RPCs need and well short of
/// a user concluding the app is broken.
const Duration retailerReadTimeout = Duration(seconds: 20);

/// Classifies a thrown Retailer read.
///
/// ## Discrimination is by type and machine code only
///
/// Nothing here reads `error.message`, for display or for branching. Postgres
/// messages name tables, columns, functions and policies; GoTrue messages are
/// prose that changes between releases and can carry account detail. The backend
/// contract is explicit that message text is not an API, so neither is read and
/// neither travels onward — only a [RetailerReadProblem] does.
///
/// Note in particular that the three raising RPCs use
/// `raise ... using errcode = 'insufficient_privilege'` with three *different*
/// English messages ("Not authorized to view staff", "…staff invitations",
/// "…assigned products"). All three classify identically here, because the
/// SQLSTATE is what carries meaning and the sentence is not part of the
/// contract.
///
/// ## Why transport is split from "unexpected"
///
/// `mapSupabaseError` folds every unrecognised throw into `UnavailableFailure`.
/// On these screens that would report a programming error, an unreadable
/// response and a genuine outage with the same sentence. So the two
/// connection-shaped failures are identified positively, and everything
/// unidentified degrades to [RetailerReadProblem.unexpected] rather than
/// borrowing their message.
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
/// never an empty list.
RetailerReadProblem classifyRetailerReadError(Object error) {
  if (error is TimeoutException) {
    return RetailerReadProblem.timeout;
  }

  // Checked before PostgrestException: the transport exception is what the SDK
  // propagates when the request never arrived, and it carries no SQLSTATE to
  // classify.
  if (error is http.ClientException) {
    return RetailerReadProblem.network;
  }

  if (error is sb.PostgrestException) {
    return switch (error.code) {
      SqlState.insufficientPrivilege => RetailerReadProblem.denied,
      // A recognised SQLSTATE these RPCs have no business raising, or none at
      // all. All four reads are `STABLE` and touch no constraint, so a
      // duplicate, a check violation or a prerequisite-state error would mean
      // the deployed functions are not the ones this build expects.
      _ => RetailerReadProblem.unexpected,
    };
  }

  if (error is sb.AuthException) {
    // The session is absent, expired or rejected. Deliberately not bound to a
    // message: auth exceptions can carry token material.
    return RetailerReadProblem.signedOut;
  }

  return RetailerReadProblem.unexpected;
}
