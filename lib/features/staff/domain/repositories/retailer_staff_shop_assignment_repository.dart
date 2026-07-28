import '../entities/retailer_staff_shop_assignment.dart';

/// The outcome of one shop-assignment replacement.
///
/// Two cases, and the split is the point: either the function committed and
/// answered in its own vocabulary, or it did not. Every decision about what to
/// tell the person, whether to re-read the roster, and whether the editor may
/// stay armed is made from one of the two — never from an HTTP status this type
/// does not carry.
sealed class RetailerStaffShopAssignmentResult {
  const RetailerStaffShopAssignmentResult();
}

/// The replacement committed, and the counts describe what it changed.
///
/// The write is a single statement inside one `SECURITY DEFINER` function, so
/// this is a **transactional** answer: the retirements, the insertions and the
/// audit row either all happened or none did. There is no partial success to
/// model and no half-applied state to reconcile.
final class RetailerStaffShopAssignmentApplied
    extends RetailerStaffShopAssignmentResult {
  const RetailerStaffShopAssignmentApplied(this.change);

  /// A **change summary**, never a total. See
  /// [RetailerStaffShopAssignmentChange].
  final RetailerStaffShopAssignmentChange change;
}

/// No committed answer: a refusal, a transport fault, a timeout, or a reply this
/// build could not read.
///
/// Never carries a SQLSTATE, a PostgreSQL message, a PostgREST detail or hint, a
/// function or table name, a membership id, a shop id, a stack trace, a project
/// URL or a token — the type has no field any of those could occupy.
final class RetailerStaffShopAssignmentRefused
    extends RetailerStaffShopAssignmentResult {
  const RetailerStaffShopAssignmentRefused(this.problem);

  final RetailerStaffShopAssignmentProblem problem;
}

/// The Retailer staff **shop-assignment** write, and nothing else.
///
/// ## One method, and its signature is the security property
///
/// The only thing a caller may nominate is a
/// [RetailerStaffShopAssignmentRequest], which itself holds exactly the two
/// values the deployed function declares. There is no Retailer organization id,
/// actor / auth-user / profile id, member-role id, invitation id, email, role
/// code, permission code, current-assignment list, separate add and remove
/// lists, audit field, status, timestamp, token or idempotency key anywhere on
/// this interface, and no place to add one without changing this file.
///
/// ## Why this is separate from the two staff interfaces that already exist
///
/// `RetailerStaffRepository` documents that it holds **no write**, and both of
/// its methods are nullary reads of `STABLE` functions; adding a write would
/// falsify that guarantee for the roster and the invitation history as well.
/// `RetailerStaffInvitationRepository` is about invitations, which this
/// operation deliberately is not — it changes an **already accepted**
/// membership, on a different permission (`RETAILER_STAFF_SHOP_ASSIGN`), with no
/// email, no token and no expiry anywhere near it.
///
/// ## What is deliberately absent
///
/// No staff activation or deactivation, no role change, no invitation accept,
/// revoke or resend, no shop create/edit/status write, and no zero-shop
/// stand-down. Every one of those is a different backend operation this
/// milestone does not implement, and none has a method here.
///
/// ## Nothing retries
///
/// [setShopAssignments] performs exactly one call and returns whatever came of
/// it. A repeat is a deliberate human decision made on a screen: the operation
/// is idempotent in its effect, but a silent second call after an *unknown*
/// outcome would write an audit row for a change nobody asked for twice, and
/// could overwrite an edit somebody else made in between.
abstract interface class RetailerStaffShopAssignmentRepository {
  /// `public.set_retailer_staff_shop_assignments(uuid, uuid[])`.
  ///
  /// Replaces the target membership's **visible ACTIVE** shop assignments with
  /// the request's complete desired set, in one round trip, on the caller's own
  /// session.
  ///
  /// ## What the backend does with it, and what it does not
  ///
  /// It derives the Retailer from `auth.uid()`, re-checks
  /// `RETAILER_STAFF_SHOP_ASSIGN`, matches the membership against *that*
  /// Retailer, confirms the target is an active Sales Staff member, validates
  /// every submitted shop as that Retailer's ACTIVE shop, then retires what is
  /// missing with `removed_at`, inserts what is new, leaves the rest untouched,
  /// and writes the audit row — all in one transaction.
  ///
  /// **Assignments to non-ACTIVE shops are preserved.** They are invisible to
  /// this client, they are not named in the request, and the function does not
  /// retire them. Nothing here may be described as replacing every assignment a
  /// member holds.
  ///
  /// ## The response is a change summary, not a state
  ///
  /// Three counts, and no assignment rows. The canonical roster read is the only
  /// authority on what the member's assignments now are, which is why a caller
  /// re-reads it rather than assembling a row from what it just sent.
  Future<RetailerStaffShopAssignmentResult> setShopAssignments(
    RetailerStaffShopAssignmentRequest request,
  );
}
