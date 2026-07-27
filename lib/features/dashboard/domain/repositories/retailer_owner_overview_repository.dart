import '../entities/retailer_owner_overview.dart';

/// Why a Retailer Owner overview read did not produce a row.
///
/// ## Why this exists rather than a bare `Failure`
///
/// The shared [Failure] contract collapses every transport, serialization and
/// unrecognised backend fault into one `UnavailableFailure`, whose copy is
/// *"Check your connection and try again."* That is right for most screens and
/// wrong for this one: it is the first thing a Retailer Owner sees after signing
/// in, so "we could not reach the service", "the service answered something this
/// build cannot read" and "something in our own code broke" would all be
/// reported as a connection problem — sending someone to fix a connection that
/// is working.
///
/// This is the same shape `SignInFailureReason` gives the login form, and it is
/// deliberately **not** a widening of `Failure`. Adding members to a shared
/// sealed type to satisfy one screen would change the copy on every screen that
/// switches over it.
///
/// ## What is deliberately absent
///
/// There is no member for "inactive membership" or "suspended Retailer", because
/// the backend does not distinguish them. `get_retailer_owner_portal_context()`
/// returns **zero rows** for a suspended profile, an INVITED or inactive
/// membership, a suspended or deactivated organization, a missing role, a
/// missing permission and the ambiguous multi-Retailer case alike — so that it
/// cannot be used as an oracle to learn why access failed or whether an account
/// exists. All of them arrive here as [ineligible], and inventing a reason for
/// them in Dart would be fabricating a distinction the database refused to make.
///
/// The two statuses *are* still modelled and shown — but as fields of a row that
/// was returned, never as an explanation for one that was not. See
/// [RetailerOwnerOverview.isFullyActive].
enum RetailerOverviewProblem {
  /// `42501`. The caller is signed in and refused.
  ///
  /// Distinct from [ineligible]: a refusal is the backend raising, whereas
  /// ineligibility is the backend answering successfully with nothing. In the
  /// deployed contract this RPC does not raise `42501` at all — it answers
  /// empty — so this arrives only from a future or reconfigured backend.
  denied,

  /// There is no verified session. Not a refusal: the caller is not signed in
  /// rather than signed in and refused.
  signedOut,

  /// The response could not be understood — wrong shape, a required field
  /// missing or null, a status that is not a string, a negative count, or an
  /// active count exceeding the total.
  ///
  /// Never rendered as an empty overview. "This build could not read the answer"
  /// and "you have no shops" are opposite claims.
  malformed,

  /// The request never reached the backend: no route, no DNS answer, a refused
  /// TLS handshake, a blocked socket, a browser CORS refusal.
  ///
  /// The **only** member whose copy mentions the connection.
  network,

  /// The request was sent and nothing came back in time.
  timeout,

  /// Anything else — an unexpected SDK state or a programming error. Not a
  /// statement about the user's network.
  unexpected,
}

/// The outcome of the one Retailer Owner overview read.
///
/// Three cases, because the backend genuinely produces three kinds of answer and
/// flattening any pair of them would state something false:
///
/// * [RetailerOverviewLoaded] — one row.
/// * [RetailerOverviewIneligible] — zero rows. A **successful** answer.
/// * [RetailerOverviewFailed] — no answer at all.
sealed class RetailerOverviewResult {
  const RetailerOverviewResult();
}

/// The row. Already parsed into domain values — no raw Supabase map travels
/// past the data layer.
final class RetailerOverviewLoaded extends RetailerOverviewResult {
  const RetailerOverviewLoaded(this.overview);

  final RetailerOwnerOverview overview;
}

/// The backend answered, successfully, with no row.
///
/// Not a failure and never presented as one: there is nothing to retry, because
/// a second identical call returns the same nothing. The screen says so plainly
/// and offers the account surface rather than a "Try again" button.
final class RetailerOverviewIneligible extends RetailerOverviewResult {
  const RetailerOverviewIneligible();
}

/// The read did not produce an answer.
final class RetailerOverviewFailed extends RetailerOverviewResult {
  const RetailerOverviewFailed(this.problem);

  final RetailerOverviewProblem problem;
}

/// The one Retailer Owner Overview read, and nothing else.
///
/// ## The signature is the security property
///
/// [overview] takes **no arguments at all**. There is no Retailer organization
/// id, auth user id, profile id, membership id, tenant id, role code, permission
/// code, status or date range anywhere on this interface — not as an optional,
/// not as a named argument with a default.
///
/// The absence is the point, and it mirrors the deployed function exactly:
/// `public.get_retailer_owner_portal_context()` is declared with an empty
/// parameter list and resolves the organization inside
/// `resolve_retailer_owner_organization('RETAILER_PORTAL_READ')`, which derives
/// the caller from `auth.uid()`. There is nothing for a client to supply and
/// therefore nothing for a client to forge — a Retailer id cannot be accepted
/// from a route parameter, local storage or user input because there is no
/// parameter to accept it through.
///
/// ## This milestone is read-only, and the interface is the proof
///
/// There is no write, edit, recompute or export method here, and no place to add
/// one without changing this file. The backend function is declared `STABLE` and
/// contains no insert, update or delete; reading a count is not an event, so this
/// call writes no audit row of its own either.
///
/// ## No shop, staff or product read
///
/// `list_retailer_owner_portal_shops()`, `list_retailer_staff_members()` and
/// `list_retailer_assigned_products()` are all deployed and all out of scope.
/// The two shop counts on this interface come from the overview row itself,
/// computed in SQL, which is exactly why the Overview needs no shop list to
/// render a shop count.
abstract interface class RetailerOwnerOverviewRepository {
  /// `public.get_retailer_owner_portal_context()` — the whole overview, in one
  /// round trip.
  ///
  /// Returns [RetailerOverviewIneligible] for zero rows, which is a real answer
  /// and not an error. Every genuine fault is a [RetailerOverviewFailed]
  /// carrying one [RetailerOverviewProblem]; a malformed body is never rendered
  /// as an overview of zeros, and a refusal is never rendered as an empty
  /// organization.
  Future<RetailerOverviewResult> overview();
}
