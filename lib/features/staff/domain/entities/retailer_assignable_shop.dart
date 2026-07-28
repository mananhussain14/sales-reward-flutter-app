import 'package:equatable/equatable.dart';

/// One row of `public.list_retailer_staff_assignable_shops()`.
///
/// ## This is the one Retailer entity that legitimately holds an id
///
/// Every other Retailer read in this application deliberately carries no
/// identifier, because the deployed contracts return none and nothing on those
/// screens is addressable. This contract is the exception, and the migration
/// says why in as many words: shop ids exist here *"so it can be passed straight
/// back to reserve_retailer_staff_invitation"*, which is the only legitimate
/// reason to hand one to a client today.
///
/// So [id] is bounded by that purpose:
///
/// * it is **never displayed** — the picker renders [name], [code] and [city];
/// * it is **never persisted**;
/// * it is **never typed, derived from a name, or read from a route** — the only
///   values that can reach an invitation are ones this read returned;
/// * it travels to exactly one place, the `shopIds` array of the shared
///   `send-retailer-staff-invitation` request.
///
/// ## Only active shops exist here
///
/// The function filters `status = 'ACTIVE'` itself, matching what the
/// reservation will accept, so there is no status column on this contract and no
/// status field on this type. A suspended or deactivated shop is not "shown as
/// unavailable" — it is absent, because offering it would produce a picker whose
/// selections the reservation refuses. This client adds no status filter of its
/// own and could not: there is nothing to filter on.
final class RetailerAssignableShop extends Equatable {
  const RetailerAssignableShop({
    required this.id,
    required this.name,
    required this.code,
    required this.city,
  });

  /// `retailer_shops.id`. The value sent back as one element of `shopIds`.
  ///
  /// Never rendered. See the class doc for the whole of its permitted life.
  final String id;

  /// `retailer_shops.name`. `NOT NULL` and non-blank
  /// (`retailer_shops_name_not_empty`).
  final String name;

  /// `retailer_shops.code` — nullable in the schema, so null means "no code
  /// recorded" and is rendered as an absence rather than an empty string.
  final String? code;

  /// `retailer_shops.city` — nullable, on the same terms.
  final String? city;

  /// The name plus whatever else was recorded, for a picker label.
  ///
  /// Display only. It is not an identifier and is never sent: two shops may
  /// legitimately share a name and a city, which is precisely why the selection
  /// is keyed on [id] and never on this.
  String get displayLabel {
    final List<String> extras = <String>[?code, ?city];
    return extras.isEmpty ? name : '$name · ${extras.join(' · ')}';
  }

  @override
  List<Object?> get props => <Object?>[id, name, code, city];
}
