/// Whether a campaign combines with others.
///
/// `campaign_versions.stacking_mode`, constrained by
/// `campaign_versions_stacking_allowed` to exactly two values.
///
/// ## The mode is returned; the key and the ranking are not
///
/// `campaign_versions` also carries `exclusivity_key` and `priority`, and
/// **neither reaches this client**. Both role contracts withhold them
/// deliberately, and the migration says why: the key and the ranking are *"the
/// Vendor's competition configuration between its own campaigns"*, whereas the
/// mode *"changes what a seller can expect to earn"*.
///
/// So there is no field here for either, nothing to hold one, and no screen that
/// could render one. An exclusive campaign is described by what it means for the
/// reader — this one applies, not several — and never by which key it competes
/// on or where it ranks.
enum CampaignStackingMode {
  /// Can apply alongside other campaigns that also allow it.
  stackable('STACKABLE'),

  /// Competes with other exclusive campaigns; one applies to a given sale.
  exclusive('EXCLUSIVE');

  const CampaignStackingMode(this.code);

  /// The backend token. **Never rendered** — wording comes from `CampaignCopy`.
  final String code;

  /// The mode [raw] names, or null if this build does not recognise it.
  static CampaignStackingMode? tryFromCode(String raw) {
    for (final CampaignStackingMode mode in values) {
      if (mode.code == raw) {
        return mode;
      }
    }
    return null;
  }

  bool get isExclusive => this == exclusive;
}
