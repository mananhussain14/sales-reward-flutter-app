import 'package:equatable/equatable.dart';

/// Which of a Vendor's products a campaign counts.
///
/// `campaign_versions.product_scope`, constrained by
/// `campaign_versions_product_scope_allowed`.
enum CampaignProductScope {
  /// A fixed set chosen when the version was published.
  selectedProducts('SELECTED_PRODUCTS'),

  /// Whatever the Vendor has assigned to the Retailer, while it is eligible.
  allEligibleProducts('ALL_ELIGIBLE_PRODUCTS');

  const CampaignProductScope(this.code);

  /// The backend token. **Never rendered** — wording comes from `CampaignCopy`.
  final String code;

  /// The scope [raw] names, or null if this build does not recognise it.
  static CampaignProductScope? tryFromCode(String raw) {
    for (final CampaignProductScope scope in values) {
      if (scope.code == raw) {
        return scope;
      }
    }
    return null;
  }
}

/// *When* the product set was decided.
///
/// `campaign_versions.product_eligibility_resolution`, constrained by
/// `campaign_versions_resolution_allowed`.
enum CampaignProductEligibilityResolution {
  /// Frozen at publication. The set cannot change afterwards, and a later
  /// assignment change cannot alter it.
  snapshot('SNAPSHOT'),

  /// Resolved from the assignment **timeline**, at one documented instant:
  /// `least(now(), coalesce(ends_at, 'infinity'))`.
  ///
  /// A running, scheduled, paused or evergreen campaign resolves at `now()`; a
  /// campaign whose period has passed resolves at its own `ends_at`, so a
  /// historical campaign reports what was eligible when it stopped rather than
  /// today's catalogue.
  liveTemporal('LIVE_TEMPORAL');

  const CampaignProductEligibilityResolution(this.code);

  /// The backend token. **Never rendered** — wording comes from `CampaignCopy`.
  final String code;

  /// The resolution [raw] names, or null if this build does not recognise it.
  static CampaignProductEligibilityResolution? tryFromCode(String raw) {
    for (final CampaignProductEligibilityResolution resolution in values) {
      if (resolution.code == raw) {
        return resolution;
      }
    }
    return null;
  }
}

/// The product rule, as one value: a scope, its resolution, and how many
/// products are eligible **for the reading Retailer**.
///
/// ## Why the scope and the resolution are one type
///
/// Because the database says they are one fact. `campaign_versions` carries the
/// pairing as a structural equivalence, not as two independent columns:
///
/// ```sql
/// constraint campaign_versions_resolution_matches_scope
///   check (
///     (product_scope = 'SELECTED_PRODUCTS')
///     = (product_eligibility_resolution = 'SNAPSHOT')
///   )
/// ```
///
/// The migration's own reasoning is that a `SELECTED_PRODUCTS` version claiming
/// `LIVE_TEMPORAL` *"would silently ignore its own frozen snapshot"*, and an
/// `ALL_ELIGIBLE_PRODUCTS` version claiming `SNAPSHOT` *"would freeze a list its
/// own name says is open-ended"*. Both combinations are refused at the table.
///
/// So this type refuses them too — [isCoherent] is asserted by the parser, and a
/// row carrying an impossible pair is a malformed response rather than a
/// campaign to render. Modelling them as two loose fields would have made the
/// impossible pair representable in Dart and left every wording branch to guess
/// which column to believe.
///
/// ## The count is this Retailer's, and it is never recomputed here
///
/// `eligible_product_count` is resolved server-side against the reading
/// Retailer — from the frozen snapshot under [CampaignProductScope.selectedProducts],
/// and from the assignment timeline at the documented instant otherwise. It is
/// never the campaign's total across Retailers, and **nothing in this feature
/// derives it from the product list**: the two come from different RPCs, and
/// recomputing one from the other would put a second definition of eligibility
/// on the device.
///
/// A count of **zero is a real and important answer** — see [hasNoEligibleProducts].
final class CampaignProductEligibility extends Equatable {
  const CampaignProductEligibility({
    required this.scope,
    required this.resolution,
    required this.eligibleProductCount,
  });

  final CampaignProductScope scope;
  final CampaignProductEligibilityResolution resolution;

  /// How many products are eligible for the **reading** Retailer.
  ///
  /// Non-negative; a negative value is refused by the parser as impossible.
  final int eligibleProductCount;

  /// Whether the pair is one the backend can actually store.
  ///
  /// Asserted by the parser rather than by an assertion in the constructor, so
  /// that a bad response becomes a handled read failure instead of a crash.
  bool get isCoherent =>
      (scope == CampaignProductScope.selectedProducts) ==
      (resolution == CampaignProductEligibilityResolution.snapshot);

  /// The Retailer has nothing that could earn under this campaign.
  ///
  /// Preserved as the honest zero it is. It is **not** a reason to hide the
  /// campaign, not an error, and not something the reader can repair — it is a
  /// consequence of which products the Vendor has assigned, which is a Vendor
  /// action on a different surface entirely.
  bool get hasNoEligibleProducts => eligibleProductCount == 0;

  @override
  List<Object?> get props => <Object?>[scope, resolution, eligibleProductCount];
}
