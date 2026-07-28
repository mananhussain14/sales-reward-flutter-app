import '../../../../core/parsing/rpc_row.dart';
import '../../domain/entities/retailer_staff_shop_assignment.dart';

/// Parses `set_retailer_staff_shop_assignments()`.
///
/// The deployed function is declared
/// `returns table (shops_added integer, shops_removed integer, shops_unchanged
/// integer)` and its body ends in a single `select`, so PostgREST renders it as
/// a JSON array holding **exactly one** object.
///
/// ## Why nothing here degrades to a default
///
/// This parser sits behind a **committed write**. Substituting a zero for a
/// count it could not read would report "nothing changed" about a transaction
/// that may have retired three shops and added two — a sentence that is not
/// merely imprecise but false, and one a person would act on. So every
/// malformation is refused, and the caller reports the honest thing: the change
/// may well have been made, and the canonical roster is the authority on what it
/// was.
///
/// ## Which malformations are rejected
///
/// * a body that is not a list, or a row that is not an object;
/// * **no row** — an empty array. The function always projects one, so an empty
///   result is evidence the response is not this contract, and reading it as
///   "zero of everything" would invent a summary the backend never sent;
/// * **more than one row.** Two summaries for one call means the deployed
///   function is not the one this build expects, and picking the first would be
///   choosing arbitrarily between two disagreeing answers;
/// * a **missing** `shops_added`, `shops_removed` or `shops_unchanged`;
/// * a **non-integer** value — a string, a boolean, a null, or a fractional
///   number. A count is an `integer` on this contract, and `3.0` arriving where
///   an `integer` was declared means something between here and the function is
///   not what it claims;
/// * a **negative** value. It is not a small number; it is impossible for a row
///   count, and treating it as one would put a negative in a sentence.
///
/// ## What is tolerated
///
/// An **unrecognized extra key** is ignored. The contract is additive, and a
/// column added by a later migration must not break a client that does not need
/// it — the three this build reads are still present and still mean the same
/// thing.
abstract final class RetailerStaffShopAssignmentParser {
  static RetailerStaffShopAssignmentChange parse(Object? raw) {
    final List<Map<String, Object?>> rows = RpcRow.asRows(
      raw,
      'shop assignment result',
    );

    if (rows.isEmpty) {
      throw const RpcFormatException('shop assignment result has no row');
    }
    if (rows.length > 1) {
      throw const RpcFormatException(
        'shop assignment result has more than one row',
      );
    }

    final Map<String, Object?> row = rows.single;

    return RetailerStaffShopAssignmentChange(
      shopsAdded: _count(row['shops_added'], 'shops_added'),
      shopsRemoved: _count(row['shops_removed'], 'shops_removed'),
      shopsUnchanged: _count(row['shops_unchanged'], 'shops_unchanged'),
    );
  }

  /// One `integer` column that is a row count.
  ///
  /// `int` only. A `double` is refused even when it is whole: PostgREST renders
  /// an `integer` as a JSON integer, so a float arriving here means the value did
  /// not come from the declared column, and rounding it would be this build
  /// deciding what the backend meant.
  static int _count(Object? raw, String what) {
    if (raw is! int) {
      throw RpcFormatException('$what is missing or not an integer');
    }
    if (raw < 0) {
      throw RpcFormatException('$what is negative');
    }
    return raw;
  }
}
