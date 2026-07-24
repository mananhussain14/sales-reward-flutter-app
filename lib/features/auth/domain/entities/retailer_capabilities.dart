import 'package:equatable/equatable.dart';

/// A single capability, nameable as a value.
///
/// Exists so a navigation destination can declare *which* hint it depends on
/// and stay `const`. A function field would be more flexible and would make
/// every navigation model non-const, which is a poor trade for seven flags.
enum RetailerCapability {
  viewRetailerOverview,
  viewShops,
  viewStaff,
  manageStaff,
  assignStaffShops,
  viewAssignedProducts,
  submitReceipts,
}

/// What the Retailer portal may **show** this caller.
///
/// ## These are presentation hints. They are not authorization.
///
/// The backend computes each flag by calling the same resolver, with the same
/// permission code, that the operation it describes calls — so a hint cannot
/// drift from its gate. It is still only a hint: the database decides again, in
/// SQL, on every single call.
///
/// The migration is explicit about why they are resolver-derived rather than
/// permission-derived. `RETAILER_SHOPS_READ` is mapped to `RETAILER_MANAGER`, so
/// a permission-derived hint would tell both clients to render the Shops screen
/// for a Manager — while the screen's own RPC resolves through
/// `resolve_retailer_owner_organization`, which hard-filters `RETAILER_OWNER`
/// and refuses them. A Manager holds the permission and is still refused the
/// operation.
///
/// Consequently this class may be used to **hide or disable a navigation
/// destination**, and for nothing else. It must never be consulted to decide
/// whether a write is permitted, and a false flag must never be treated as
/// proof of anything — only as a reason not to advertise a dead end.
///
/// Every field defaults to `false`. A capability this build cannot read is a
/// capability it does not offer, which is the only direction that is safe.
final class RetailerCapabilities extends Equatable {
  const RetailerCapabilities({
    this.viewRetailerOverview = false,
    this.viewShops = false,
    this.viewStaff = false,
    this.manageStaff = false,
    this.assignStaffShops = false,
    this.viewAssignedProducts = false,
    this.submitReceipts = false,
  });

  /// Nothing is offered. The conservative value, used when a capability block
  /// cannot be read at all.
  static const RetailerCapabilities none = RetailerCapabilities();

  /// `get_retailer_owner_portal_context()` — owner / `RETAILER_PORTAL_READ`.
  final bool viewRetailerOverview;

  /// `list_retailer_owner_portal_shops()` — owner / `RETAILER_SHOPS_READ`.
  final bool viewShops;

  /// `list_retailer_staff_members()` — member / `RETAILER_STAFF_READ`.
  final bool viewStaff;

  /// `list_retailer_staff_invitations()` — member / `RETAILER_STAFF_MANAGE`.
  final bool manageStaff;

  /// `list_retailer_staff_assignable_shops()` — member /
  /// `RETAILER_STAFF_SHOP_ASSIGN`.
  final bool assignStaffShops;

  /// `list_retailer_assigned_products()` — member / `RETAILER_PRODUCTS_READ`.
  final bool viewAssignedProducts;

  /// `list_my_assigned_receipt_shops()` — member / `RECEIPT_SUBMIT`.
  final bool submitReceipts;

  /// Whether [capability] is offered.
  ///
  /// Presentation only — a true answer means "do not hide this destination",
  /// never "this operation will succeed".
  bool allows(RetailerCapability capability) => switch (capability) {
    RetailerCapability.viewRetailerOverview => viewRetailerOverview,
    RetailerCapability.viewShops => viewShops,
    RetailerCapability.viewStaff => viewStaff,
    RetailerCapability.manageStaff => manageStaff,
    RetailerCapability.assignStaffShops => assignStaffShops,
    RetailerCapability.viewAssignedProducts => viewAssignedProducts,
    RetailerCapability.submitReceipts => submitReceipts,
  };

  /// Whether every flag is false.
  ///
  /// A Retailer context in this state is a backend inconsistency rather than a
  /// meaningful answer, and callers should fall back to showing the role's full
  /// navigation rather than rendering an empty shell.
  bool get isEmpty =>
      !viewRetailerOverview &&
      !viewShops &&
      !viewStaff &&
      !manageStaff &&
      !assignStaffShops &&
      !viewAssignedProducts &&
      !submitReceipts;

  @override
  List<Object?> get props => <Object?>[
    viewRetailerOverview,
    viewShops,
    viewStaff,
    manageStaff,
    assignStaffShops,
    viewAssignedProducts,
    submitReceipts,
  ];
}
