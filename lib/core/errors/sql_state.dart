/// The deliberate SQLSTATEs the SalesReward backend raises.
///
/// Documented in § 8.1 of `docs/mobile-architecture-recommendation.md` in the
/// `salesreward-admin` repository. These four codes — and nothing else — are the
/// machine-readable half of the error contract. The accompanying English message
/// is **not** part of the contract and must never be parsed.
abstract final class SqlState {
  /// `insufficient_privilege`.
  ///
  /// Deliberately overloaded: it means "you are not authorized", "that id does
  /// not exist", and "that id belongs to someone else", with byte-identical
  /// messages for all three so that none of them is an existence oracle.
  ///
  /// The mobile client must preserve that. Never render "not found" where the
  /// backend said `42501`.
  static const String insufficientPrivilege = '42501';

  /// `unique_violation` — a duplicate owner, shop code, product code/barcode, or
  /// receipt hash.
  static const String uniqueViolation = '23505';

  /// `check_violation` — input shape or a business rule.
  static const String checkViolation = '23514';

  /// `object_not_in_prerequisite_state` — an inactive relationship, retailer, or
  /// product.
  static const String objectNotInPrerequisiteState = '55000';
}
