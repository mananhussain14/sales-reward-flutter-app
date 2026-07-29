import '../entities/retailer_staff_lifecycle_status.dart';

/// Why a lifecycle change did not happen.
///
/// A discriminant rather than a sentence: the wording lives in the presentation
/// copy, so no message can ever be built from a backend response. The type has
/// **no field** a SQLSTATE, a PostgreSQL message, a PostgREST detail, a function
/// or table name, a membership id, a role code, a stack trace, a project URL or
/// a token could occupy.
///
/// ## `denied` is deliberately one member for eleven causes
///
/// The deployed function raises `42501` with one byte-identical message for: not
/// signed in; lacking `RETAILER_STAFF_MANAGE`; resolving to zero or to several
/// Retailers; and a target that is unknown, another Retailer's, **the caller
/// themselves**, a `RETAILER_OWNER`, **multi-role**, role-less, `INVITED` or
/// `SUSPENDED`. Telling any of them apart here would hand back exactly the
/// existence oracle that single message exists to deny — a caller could sweep
/// membership ids to learn another Retailer's org chart.
enum RetailerStaffLifecycleProblem {
  /// `42501`. See the enum doc: one answer for every refusal.
  denied,

  /// `23514` — the requested status was not exactly `ACTIVE` or `DEACTIVATED`.
  ///
  /// Unreachable from this application's own UI, which can only produce the two
  /// tokens of [RetailerStaffLifecycleStatus]. Modelled because the backend
  /// raises it and a client that could not name it would report a defect as an
  /// outage.
  invalidStatus,

  /// `55000` — **the acting Retailer** stopped being ACTIVE between the
  /// authorization resolve and the row lock.
  ///
  /// A fact about the caller's own organization, not about the target. It is
  /// therefore safe to word specifically, unlike [denied].
  retailerUnavailable,

  /// `22P02` — a value could not be cast to `uuid`. Raised by PostgreSQL's type
  /// system before the function body runs, so it is a defect in the request
  /// rather than anything the person did.
  malformedRequest,

  /// There is no verified session on this device. Not a refusal: the caller is
  /// not signed in rather than signed in and refused.
  signedOut,

  /// The request never reached the backend.
  network,

  /// The request was sent and nothing came back in time.
  ///
  /// The outcome is genuinely **unknown**: the function may have committed after
  /// this client stopped waiting. The copy for it points at the roster rather
  /// than at the button, and nothing retries.
  timeout,

  /// Anything else. Not a statement about the user's network.
  unexpected,
}

/// The outcome of one staff lifecycle change.
///
/// Three cases, not two, and the third is the one that matters.
///
/// A read either answered or did not, and a read that did not answer changed
/// nothing. A write is different: it can leave the database changed while
/// leaving *this client* unable to describe the change. So there is a case for
/// "it definitely did not happen" ([RetailerStaffLifecycleRefused]) and a
/// separate case for "it happened, but the answer could not be read"
/// ([RetailerStaffLifecycleUnconfirmed]) — because the safe response to those
/// two is opposite. One may be attempted again. The other must never be retried,
/// automatically or by a re-armed button.
sealed class RetailerStaffLifecycleResult {
  const RetailerStaffLifecycleResult();
}

/// The change committed **and** its answer was understood.
///
/// [confirmedStatus] is the status the database reported the membership now
/// holds — never the status that was requested. The two agree on the ordinary
/// path; stating the database's answer is what keeps this honest when they do
/// not.
///
/// [statusChanged] is the RPC's own `status_changed`. It is carried because "you
/// did that" and "somebody already had" are different things to an Owner: a
/// request for the status a membership already holds performs no `UPDATE`,
/// writes no audit row, and **preserves the original `deactivated_at`** — it is
/// an idempotent no-op reported honestly rather than as a conflict.
final class RetailerStaffLifecycleApplied extends RetailerStaffLifecycleResult {
  const RetailerStaffLifecycleApplied({
    required this.confirmedStatus,
    required this.statusChanged,
  });

  final RetailerStaffLifecycleStatus confirmedStatus;
  final bool statusChanged;
}

/// The change **succeeded**, but its answer could not be described.
///
/// Reachable from exactly one place: a call the SDK reported no error for —
/// which means the transaction **committed** — whose body the strict parser
/// could not trust. Every parse failure lands here: zero rows, several rows, a
/// missing, malformed or *wrong* membership id, an out-of-vocabulary status, and
/// a non-boolean change flag.
///
/// Three rules follow, and all three are the point of having this case:
///
/// * **never reported as a failure** — telling an Owner a colleague was not
///   deactivated when they were is the worst answer available;
/// * **never reported as "unchanged"** — that would claim nothing happened when
///   somebody may have just lost access;
/// * **never retried.** There is nothing left to retry. The canonical roster is
///   re-read instead, because it is the only authority on what the membership
///   now holds.
final class RetailerStaffLifecycleUnconfirmed
    extends RetailerStaffLifecycleResult {
  const RetailerStaffLifecycleUnconfirmed();
}

/// The change did **not** happen — or, for [RetailerStaffLifecycleProblem.timeout]
/// and [RetailerStaffLifecycleProblem.unexpected], could not be established.
///
/// Every deployed refusal raises, and a raise rolls the whole function back — no
/// status change, no `deactivated_at` move and no audit row. So for the four
/// SQLSTATE members a caller may safely offer another attempt.
final class RetailerStaffLifecycleRefused extends RetailerStaffLifecycleResult {
  const RetailerStaffLifecycleRefused(this.problem);

  final RetailerStaffLifecycleProblem problem;
}

/// The Retailer staff **lifecycle** write, and nothing else.
///
/// ## Why this is a separate interface
///
/// `RetailerStaffRepository` documents that it holds **no write**, and both of
/// its methods are nullary reads of `STABLE` functions; adding a write would
/// falsify that guarantee for the roster and the invitation history as well.
/// `RetailerStaffShopAssignmentRepository` is about *which shops* an already
/// accepted member works in, on a different permission
/// (`RETAILER_STAFF_SHOP_ASSIGN`), and says so. This operation is about *whether
/// they may work at all*, on `RETAILER_STAFF_MANAGE`.
///
/// One repository per contract, so each one's boundary test can assert its
/// payload vocabulary exactly.
///
/// ## What the signature makes impossible
///
/// Two values, and both are declared by the deployed function. There is no
/// Retailer organization id, actor / auth-user / profile id, member-role id,
/// role code, permission code, current status, audit action, timestamp, token or
/// idempotency key anywhere on this interface, and no place to add one without
/// changing this file.
///
/// The membership id is `organization_members.id` — the canonical address, and
/// the only identifier that can name a membership at all: one person may be
/// staff at several Retailers, so a profile id or an Auth user id would force
/// the function to guess which employment was meant.
///
/// ## Nothing retries
///
/// [setMembershipStatus] performs exactly one call and returns whatever came of
/// it. An automatic second attempt after a committed write is indistinguishable,
/// from here, from one after a failed write.
abstract interface class RetailerStaffLifecycleRepository {
  /// `public.set_retailer_staff_membership_status(p_membership_id, p_status)`.
  ///
  /// A successful response whose body cannot be trusted returns
  /// [RetailerStaffLifecycleUnconfirmed] — never a refusal, and never a
  /// fabricated success.
  Future<RetailerStaffLifecycleResult> setMembershipStatus({
    required String membershipId,
    required RetailerStaffLifecycleStatus status,
  });
}
