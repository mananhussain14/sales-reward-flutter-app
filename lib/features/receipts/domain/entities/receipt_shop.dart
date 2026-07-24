import 'package:equatable/equatable.dart';

/// One shop the signed-in Sales Staff member is actively assigned to.
///
/// Produced by `public.list_my_assigned_receipt_shops()`, which takes **zero
/// arguments**: the Retailer, the membership and the assignment are all derived
/// from `auth.uid()` in SQL. Nothing in this entity was chosen by the client,
/// and the only field that ever travels back to the backend is [shopId] — which
/// `reserve_receipt_submission` re-proves under the caller's own token before a
/// single byte is uploaded.
///
/// The RPC returns exactly three columns. No Retailer organization id, no
/// membership id, no address and no status appear here, because none of them is
/// returned.
final class ReceiptShop extends Equatable {
  const ReceiptShop({
    required this.shopId,
    required this.shopName,
    this.shopCode,
  });

  /// `shop_id` — a UUID, validated on parse.
  final String shopId;

  /// `shop_name`. `retailer_shops.name` is NOT NULL and constrained non-blank.
  final String shopName;

  /// `shop_code`. Genuinely nullable in the schema (`retailer_shops.code`), so
  /// a shop without one is ordinary rather than malformed.
  final String? shopCode;

  /// "Name · CODE", or just the name when the shop has no code.
  String get displayLabel =>
      shopCode == null ? shopName : '$shopName · $shopCode';

  @override
  List<Object?> get props => <Object?>[shopId, shopName, shopCode];
}
