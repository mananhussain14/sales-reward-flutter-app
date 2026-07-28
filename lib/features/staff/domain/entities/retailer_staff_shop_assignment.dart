import 'package:equatable/equatable.dart';

/// The 8-4-4-4-12 hexadecimal shape PostgreSQL's `uuid` type accepts.
///
/// Case-insensitive and anchored at both ends. Applied to the membership id and
/// to every submitted shop id because both become `uuid`-typed arguments: a
/// value that is not this shape is rejected by PostgreSQL's **type system** as
/// `22P02`, before the function body runs, which would turn a readable local
/// refusal into an opaque database error.
final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Which part of the editor a validation message belongs to.
enum RetailerStaffShopAssignmentField {
  /// The target membership. A problem here is a defect, never a person's
  /// mistake — the value is never typed and never chosen.
  target,

  /// The shop selection.
  shops,
}

/// What is wrong with a request that was never sent.
///
/// A discriminant rather than a sentence: the wording lives in the presentation
/// copy, so no validation message can ever be built from a backend response.
enum RetailerStaffShopAssignmentInputProblem {
  /// The target membership is absent — nothing is open for editing.
  missingTarget,

  /// A value that is not shaped like a uuid, so it cannot have come from a
  /// trusted read. A defect rather than a person's mistake.
  malformed,

  /// No shop is selected.
  ///
  /// Refused locally **and** by the backend: the deployed function raises
  /// `23514` for an empty array, because standing a Sales Staff member down to
  /// zero shops is a different operation with different consequences and is not
  /// what this editor is for.
  noShopsSelected,
}

/// The complete desired set of ACTIVE shop assignments for one membership.
///
/// ## Two values, and that is the whole payload
///
/// The deployed function is
/// `set_retailer_staff_shop_assignments(p_membership_id uuid, p_shop_ids
/// uuid[])`, and this type has exactly two fields with the same meanings.
///
/// There is no Retailer organization id, actor / auth-user / profile id, role
/// code, permission code, current assignment list, separate add and remove
/// lists, audit field, status, timestamp, token or idempotency key here, and
/// there is nowhere to put one: a request object with no such field cannot send
/// it, whatever a caller intends.
///
/// The Retailer is derived server-side from `auth.uid()`, the membership is
/// matched against *that* Retailer, and every submitted shop is validated
/// against it too. So neither id is an authorization — holding one grants
/// nothing, and another Retailer's id is refused byte-identically to one that
/// names nothing.
///
/// ## Replacement, not a diff
///
/// [shopIds] is the **complete desired ACTIVE set**, not a list of additions.
/// The backend computes the difference itself: it retires what is missing by
/// stamping `removed_at`, leaves what is present untouched, and inserts what is
/// new. Sending a diff would put that computation in two places, and the client
/// would be the one working from a snapshot.
///
/// ## What the set cannot express, deliberately
///
/// It names only shops that are currently **ACTIVE and assignable**, because
/// those are the only ones any read offers. A live assignment to a suspended or
/// deactivated shop is invisible to this client and is **preserved** by the
/// function — this request neither can nor should try to remove one.
///
/// ## Canonical by construction
///
/// [validated] is the only way to build one. It lower-cases and de-duplicates
/// the ids and sorts them, so two selections of the same shops produce the same
/// request regardless of the order the boxes were ticked, and a duplicate can
/// never reach a `uuid[]` the function would collapse silently.
///
/// ## Backend validation remains authoritative
///
/// Nothing here reproduces a backend rule. Whether the membership is this
/// caller's Retailer's, whether it is Sales Staff, whether it is active, whether
/// the Retailer itself is trading and whether each shop is ACTIVE and belongs to
/// that Retailer are all questions only the function can answer, and this type
/// does not guess at any of them.
final class RetailerStaffShopAssignmentRequest extends Equatable {
  const RetailerStaffShopAssignmentRequest._({
    required this.membershipId,
    required this.shopIds,
  });

  /// Validates and canonicalizes an editor selection.
  ///
  /// Returns [RetailerStaffShopAssignmentValid] with a canonical request, or
  /// [RetailerStaffShopAssignmentInvalid] with one problem per offending part.
  ///
  /// [shopIds] is expected to have already been intersected with the options the
  /// backend returned — that intersection is the cubit's job, because only it
  /// knows which read the options came from. What is checked here is the shape
  /// of what remains: a target exists, every id could be a uuid, and the set is
  /// not empty.
  static RetailerStaffShopAssignmentInput validated({
    required String? membershipId,
    required List<String> shopIds,
  }) {
    final Map<
      RetailerStaffShopAssignmentField,
      RetailerStaffShopAssignmentInputProblem
    >
    problems =
        <
          RetailerStaffShopAssignmentField,
          RetailerStaffShopAssignmentInputProblem
        >{};

    final String canonicalMembership = (membershipId ?? '')
        .trim()
        .toLowerCase();

    if (canonicalMembership.isEmpty) {
      problems[RetailerStaffShopAssignmentField.target] =
          RetailerStaffShopAssignmentInputProblem.missingTarget;
    } else if (!_uuidShape.hasMatch(canonicalMembership)) {
      problems[RetailerStaffShopAssignmentField.target] =
          RetailerStaffShopAssignmentInputProblem.malformed;
    }

    // Canonicalized before the rules are applied, so "empty" and "duplicated"
    // are decided on the values that would actually be sent rather than on their
    // spelling. Duplicates are folded rather than refused: the selection is held
    // in a Set upstream, so a duplicate here is a defect in a caller rather than
    // something a person did, and sending one anyway is the only outcome worth
    // preventing.
    final List<String> canonicalShops = shopIds
        .map((String id) => id.trim().toLowerCase())
        .toSet()
        .toList(growable: false);

    if (canonicalShops.any((String id) => !_uuidShape.hasMatch(id))) {
      problems[RetailerStaffShopAssignmentField.shops] =
          RetailerStaffShopAssignmentInputProblem.malformed;
    } else if (canonicalShops.isEmpty) {
      problems[RetailerStaffShopAssignmentField.shops] =
          RetailerStaffShopAssignmentInputProblem.noShopsSelected;
    }

    if (problems.isNotEmpty) {
      return RetailerStaffShopAssignmentInvalid(
        Map<
          RetailerStaffShopAssignmentField,
          RetailerStaffShopAssignmentInputProblem
        >.unmodifiable(problems),
      );
    }

    final List<String> sorted = List<String>.of(canonicalShops)..sort();

    return RetailerStaffShopAssignmentValid(
      RetailerStaffShopAssignmentRequest._(
        membershipId: canonicalMembership,
        shopIds: List<String>.unmodifiable(sorted),
      ),
    );
  }

  /// `organization_members.id`, lower-cased. Becomes `p_membership_id`.
  final String membershipId;

  /// The complete desired ACTIVE set, lower-cased, de-duplicated and sorted.
  /// Becomes `p_shop_ids`. Never empty — [validated] refuses that outright.
  final List<String> shopIds;

  @override
  List<Object?> get props => <Object?>[membershipId, shopIds];
}

/// The result of validating an editor selection.
sealed class RetailerStaffShopAssignmentInput {
  const RetailerStaffShopAssignmentInput();
}

/// The selection is well-formed and canonical.
final class RetailerStaffShopAssignmentValid
    extends RetailerStaffShopAssignmentInput {
  const RetailerStaffShopAssignmentValid(this.request);

  final RetailerStaffShopAssignmentRequest request;
}

/// The selection cannot be sent, with one problem per offending part.
final class RetailerStaffShopAssignmentInvalid
    extends RetailerStaffShopAssignmentInput {
  const RetailerStaffShopAssignmentInvalid(this.problems);

  final Map<
    RetailerStaffShopAssignmentField,
    RetailerStaffShopAssignmentInputProblem
  >
  problems;
}

/// What one committed replacement changed, as the backend counted it.
///
/// ## These are a change summary and nothing else
///
/// The three counts describe the **visible ACTIVE replacement** the request
/// asked for. In particular:
///
/// * they say nothing about assignments to non-ACTIVE shops, which the function
///   preserves untouched and never counts;
/// * `shopsAdded + shopsUnchanged` is therefore **not** the number of shops this
///   person works in, and this type deliberately exposes no `total` getter for
///   anyone to reach for. The canonical roster read is the only authority on
///   what a member's assignments now are;
/// * they are not an audit record. The function writes that itself, in the same
///   transaction.
///
/// All three are non-negative by the parser's own refusal — a negative count is
/// not a small number, it is evidence the response is not this contract.
final class RetailerStaffShopAssignmentChange extends Equatable {
  const RetailerStaffShopAssignmentChange({
    required this.shopsAdded,
    required this.shopsRemoved,
    required this.shopsUnchanged,
  });

  /// Rows inserted: shops in the request that the member did not hold.
  final int shopsAdded;

  /// Rows retired with `removed_at`: ACTIVE shops the member held that the
  /// request did not name.
  final int shopsRemoved;

  /// Rows left exactly as they were.
  final int shopsUnchanged;

  /// Whether anything actually moved.
  ///
  /// False is a real, successful answer: submitting the set a member already
  /// holds is a valid no-op the function commits and counts as all-unchanged.
  bool get hasChanges => shopsAdded > 0 || shopsRemoved > 0;

  @override
  List<Object?> get props => <Object?>[
    shopsAdded,
    shopsRemoved,
    shopsUnchanged,
  ];
}

/// Why one replacement did not commit.
///
/// ## Discriminated by SQLSTATE, never by message text
///
/// Each member below names the machine code it comes from. The accompanying
/// English sentence is not part of the contract, names tables and functions, and
/// is never read — for display or for branching.
///
/// ## `denied` is deliberately overloaded, and must stay that way
///
/// `42501` covers "you are not signed in", "you may not do this", "that
/// membership does not exist" and "that membership is another Retailer's", with
/// byte-identical messages, precisely so the operation is not an existence
/// oracle for memberships. Splitting it here on anything would rebuild the
/// oracle in Dart.
enum RetailerStaffShopAssignmentProblem {
  /// `42501` — refused, absent, or another Retailer's. See the enum doc.
  denied,

  /// `23514` — the request broke a business rule: an empty set, or a shop that
  /// is not this Retailer's ACTIVE shop.
  invalidSelection,

  /// `55000` — the Retailer itself is not in a state that permits the change.
  retailerUnavailable,

  /// `22P02` — a value could not be cast to `uuid`. A defect in the request,
  /// raised before the function body ran.
  malformedRequest,

  /// There is no verified session on this device. Not a refusal: the caller is
  /// not signed in rather than signed in and refused.
  signedOut,

  /// A reply arrived that this build could not read: a wrong shape, a missing
  /// count, a count of the wrong type, or a negative one.
  ///
  /// **Never presented as a failed write.** The call may well have committed;
  /// what failed is this build's ability to read the answer, which is why the
  /// copy for it points at the roster rather than at the button.
  malformedResponse,

  /// The request never reached the backend.
  network,

  /// The request was sent and nothing came back in time.
  ///
  /// Like [malformedResponse], the outcome is genuinely unknown: the function
  /// may have committed after this client stopped waiting.
  timeout,

  /// Anything else. Not a statement about the user's network.
  unexpected;

  /// Whether the write is known **not** to have happened.
  ///
  /// True for every refusal the backend stated in its own vocabulary and for a
  /// request that never left. False for the three that leave the outcome
  /// genuinely unknown — a timeout, an unreadable reply, and an unexpected fault
  /// after the request was sent — where the honest thing is to say so and point
  /// at the canonical roster rather than re-arm a button.
  bool get isDefinite =>
      this == denied ||
      this == invalidSelection ||
      this == retailerUnavailable ||
      this == malformedRequest ||
      this == signedOut ||
      this == network;
}
