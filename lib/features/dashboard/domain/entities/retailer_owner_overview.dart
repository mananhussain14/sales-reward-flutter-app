import 'package:equatable/equatable.dart';

/// The Retailer organization's own lifecycle state.
///
/// The closed set is `organizations_status_allowed` —
/// `check (status in ('ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`.
///
/// ## Why [unknown] exists, and what it may never do
///
/// A token this build does not recognise means the backend is newer than the
/// app. That is an additive change, so it degrades to [unknown] and renders as a
/// neutral badge rather than failing the whole read — the same rule the Vendor
/// Retailer reads apply to the same column.
///
/// [unknown] is **never** [active]. A **missing, blank or non-string** status is
/// a different thing entirely — a required value the response did not supply —
/// and the parser rejects the whole row for it.
///
/// ## Every row that exists carries `ACTIVE`
///
/// `get_retailer_owner_portal_context()` emits a row only when
/// `resolve_retailer_owner_organization` returned an organization, and that
/// resolver requires `o.status = 'ACTIVE'`. So a non-active value here is not a
/// state the deployed contract can produce. It is modelled anyway, and shown as
/// a warning rather than hidden, because the alternative is a client that
/// silently renders a suspended organization as a healthy one if the backend
/// ever changes its mind.
enum RetailerLifecycleStatus {
  /// Trading normally.
  active('ACTIVE', 'Active'),

  /// Temporarily halted.
  suspended('SUSPENDED', 'Suspended'),

  /// Ended.
  deactivated('DEACTIVATED', 'Deactivated'),

  /// A value this build does not know. Displayed neutrally, and nothing more.
  unknown('', 'Unknown');

  const RetailerLifecycleStatus(this.code, this.label);

  /// The backend token, or the empty string for [unknown].
  ///
  /// Never rendered. [label] is what reaches a screen, so an unrecognised token
  /// from the response cannot travel to the UI through this enum.
  final String code;

  /// The user-facing name.
  final String label;

  /// Maps a backend token, falling back to [unknown].
  static RetailerLifecycleStatus fromCode(String raw) {
    for (final RetailerLifecycleStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  ///
  /// A positive test against a single member rather than `!= deactivated`, so a
  /// future token can never arrive at "active" by failing to match something
  /// else.
  bool get isActive => this == active;
}

/// The caller's membership state within the Retailer organization.
///
/// A **separate closed set** from [RetailerLifecycleStatus] —
/// `organization_members_status_allowed` adds `INVITED`:
/// `check (status in ('INVITED', 'ACTIVE', 'SUSPENDED', 'DEACTIVATED'))`.
///
/// Modelled as its own enum rather than sharing one vocabulary, because they are
/// two facts about two different rows and only one of them has an `INVITED`
/// state. One enum covering both would make `INVITED` representable for an
/// organization, which the schema forbids.
enum RetailerMembershipStatus {
  /// Invited but not yet accepted.
  invited('INVITED', 'Invited'),

  /// A full member.
  active('ACTIVE', 'Active'),

  /// Temporarily halted.
  suspended('SUSPENDED', 'Suspended'),

  /// Ended.
  deactivated('DEACTIVATED', 'Deactivated'),

  /// A value this build does not know.
  unknown('', 'Unknown');

  const RetailerMembershipStatus(this.code, this.label);

  /// The backend token, or the empty string for [unknown]. Never rendered.
  final String code;

  /// The user-facing name.
  final String label;

  /// Maps a backend token, falling back to [unknown].
  static RetailerMembershipStatus fromCode(String raw) {
    for (final RetailerMembershipStatus status in values) {
      if (status != unknown && status.code == raw) {
        return status;
      }
    }
    return unknown;
  }

  /// Whether this is the one status that means "active".
  bool get isActive => this == active;
}

/// The single row `public.get_retailer_owner_portal_context()` returns.
///
/// Seven display values, and **not one of them is an identifier**. The contract
/// deliberately returns no UUID of any kind — organization, membership, profile,
/// role, permission, shop, relationship or invitation — no auth user id, no email
/// address, no personal name, no role code, no permission code and no timestamp.
/// There is nowhere in this type to put one, which is what keeps a raw UUID off
/// the screen by construction rather than by a rendering rule.
///
/// ## One snapshot, not seven fields
///
/// The backend answers all seven in a **single statement**, so they describe one
/// instant: the name, the two statuses and both counts are consistent with each
/// other. They are held together here — and replaced together by the cubit —
/// because updating one from a later read would produce a screen whose figures
/// came from two moments while claiming to be one overview.
///
/// ## Zero rows is not this type
///
/// The function returns **at most one row**, and zero rows is the single answer
/// given to every ineligible caller. That is a real, successful answer meaning
/// "there is no Owner overview for you", and it is modelled as its own result
/// case rather than as an instance of this class with empty fields. See
/// `RetailerOwnerOverviewRepository`.
final class RetailerOwnerOverview extends Equatable {
  const RetailerOwnerOverview({
    required this.retailerName,
    required this.retailerStatus,
    required this.countryCode,
    required this.defaultCurrency,
    required this.membershipStatus,
    required this.totalShopCount,
    required this.activeShopCount,
  });

  /// `organizations.name`. Non-null and non-blank in the contract.
  ///
  /// This is the one place the Retailer's name is *read*; the shell captions
  /// itself from the trusted `PortalContext` instead. The two come from the same
  /// row through two different resolvers, so they agree by construction.
  final String retailerName;

  /// `organizations.status`.
  final RetailerLifecycleStatus retailerStatus;

  /// `organizations.country_code` — an ISO 3166-1 alpha-2 code, or null.
  ///
  /// **Genuinely nullable** in the schema (`country_code is null or
  /// char_length(country_code) = 2`), so null is a real answer meaning "not
  /// recorded" and is rendered as such. It is never defaulted to a country.
  final String? countryCode;

  /// `organizations.default_currency` — an ISO 4217 code, or null.
  ///
  /// Nullable for the same reason as [countryCode] (`char_length = 3`), and
  /// never defaulted to a currency. Showing a fabricated currency on a rewards
  /// product is the kind of wrong that looks right.
  final String? defaultCurrency;

  /// `organization_members.status` for this caller in this organization.
  final RetailerMembershipStatus membershipStatus;

  /// Every shop of this organization, whatever its status.
  ///
  /// Counted in SQL against the **resolved** organization id, never a
  /// caller-supplied one — which is why the client never needs a shop id in
  /// order to count shops.
  final int totalShopCount;

  /// The `ACTIVE` subset of [totalShopCount].
  final int activeShopCount;

  /// Shops that are counted but not active.
  ///
  /// Never negative: the parser rejects a response whose active count exceeds
  /// its total, so this subtraction cannot underflow.
  int get inactiveShopCount => totalShopCount - activeShopCount;

  /// Whether both the organization and this membership are active.
  ///
  /// Drives a warning notice, never access. Nothing is unlocked or withheld on
  /// the strength of it — the backend decides that again on every call.
  bool get isFullyActive =>
      retailerStatus.isActive && membershipStatus.isActive;

  @override
  List<Object?> get props => <Object?>[
    retailerName,
    retailerStatus,
    countryCode,
    defaultCurrency,
    membershipStatus,
    totalShopCount,
    activeShopCount,
  ];
}
