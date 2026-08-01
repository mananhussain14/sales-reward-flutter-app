/// Whose eligible sales are counted toward a campaign's rule.
///
/// `campaign_versions.performance_scope`, constrained by
/// `campaign_versions_performance_allowed` to exactly two values.
///
/// ## The token is `INDIVIDUAL_STAFF`, not `INDIVIDUAL`
///
/// Worth stating because it is the one place this feature's vocabulary differs
/// from the shorthand people use when describing it. The deployed constraint is
/// `check (performance_scope = any (array['INDIVIDUAL_STAFF'::text,
/// 'RETAILER_TEAM'::text]))`, and a client that matched on `'INDIVIDUAL'` would
/// reject every individual campaign as malformed.
///
/// ## What this changes for a reader
///
/// Everything about how they should read the target. Under [individualStaff] a
/// seller's own units are counted alone; under [retailerTeam] every eligible
/// seller in the Retailer contributes to one shared count. The same
/// "25 units" reads as a personal goal in the first case and a shop-wide one in
/// the second, so the wording for the two is written separately rather than
/// parameterised — see `CampaignCopy`.
///
/// No unknown fallback, for the reason recorded on [CampaignLifecycleState]: a
/// measurement this build cannot place would make the reward sentence either
/// wrong or absent, and both are worse than refusing the row.
enum CampaignPerformanceScope {
  /// Each Sales Staff member's eligible sales are counted separately.
  individualStaff('INDIVIDUAL_STAFF'),

  /// Eligible sales across the Retailer are counted together, toward one shared
  /// target.
  retailerTeam('RETAILER_TEAM');

  const CampaignPerformanceScope(this.code);

  /// The backend token. **Never rendered** — wording comes from `CampaignCopy`.
  final String code;

  /// The scope [raw] names, or null if this build does not recognise it.
  static CampaignPerformanceScope? tryFromCode(String raw) {
    for (final CampaignPerformanceScope scope in values) {
      if (scope.code == raw) {
        return scope;
      }
    }
    return null;
  }

  /// Whether the target is shared across the Retailer.
  bool get isTeam => this == retailerTeam;
}

/// Who a campaign's reward is paid to.
///
/// `campaign_versions.reward_recipient_scope`. The deployed constraint permits
/// **exactly one** value:
///
/// ```sql
/// check (reward_recipient_scope = any (array['CONTRIBUTING_STAFF'::text]))
/// ```
///
/// ## Why a one-member enum exists at all
///
/// It is returned by both contracts, so it has to be read, and reading it as a
/// bare validated string — the `RetailerAssignedProduct.assignmentStatus`
/// precedent — was the alternative. A type is used instead because this column
/// is the one most likely to gain a second member: a campaign that paid the
/// Retailer organisation rather than the individuals who sold is an obvious
/// future rule, and the day it is added, every `switch` on this type stops
/// compiling. A validated string would compile fine and quietly keep describing
/// the new rule with the old sentence.
///
/// What is deliberately **not** built around it is a choice the data cannot
/// express: no filter, no badge, no branch in the wording. The value is constant
/// today, and presenting it as a distinction would advertise an alternative that
/// does not exist.
enum CampaignRewardRecipientScope {
  /// The Sales Staff who contributed the eligible sales.
  contributingStaff('CONTRIBUTING_STAFF');

  const CampaignRewardRecipientScope(this.code);

  final String code;

  /// The scope [raw] names, or null if this build does not recognise it.
  static CampaignRewardRecipientScope? tryFromCode(String raw) {
    for (final CampaignRewardRecipientScope scope in values) {
      if (scope.code == raw) {
        return scope;
      }
    }
    return null;
  }
}
