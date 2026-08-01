/// Where a campaign stands **right now**, as the backend derives it.
///
/// This is `campaign_derived_state(status, starts_at, ends_at)`, not the stored
/// `campaigns.status` column. The distinction is the whole point of the helper
/// and is worth restating here, because a client that confused the two would
/// show a finished campaign as running:
///
/// ```sql
/// when p_status = 'DRAFT'     then 'DRAFT'
/// when p_status = 'CANCELLED' then 'CANCELLED'
/// when p_starts_at is null    then 'DRAFT'
/// when p_ends_at is not null and now() > p_ends_at then 'ENDED'
/// when p_status = 'PAUSED'    then 'PAUSED'
/// when now() < p_starts_at    then 'SCHEDULED'
/// else 'ACTIVE'
/// ```
///
/// `ENDED` outranks `PAUSED`, and neither is a stored value — a campaign whose
/// period has passed reports `ENDED` with no job having to sweep it, and this
/// client must not recompute that from the dates itself. **No comparison against
/// the device clock happens anywhere in this feature**; the phone's clock can be
/// wrong, and the backend has already answered.
///
/// ## Why there is no `unknown` member
///
/// The Vendor Product and Retailer enums degrade an unrecognised token to
/// `unknown` and render a neutral badge, because a status there is decoration
/// beside a name a Vendor still needs to see. This vocabulary is different: it
/// decides which section a campaign is filed under, whether the zero-product
/// warning is shown at all, and whether a user is told a reward is available
/// now. A token this build cannot place is refused by the parser instead — see
/// `CampaignParsers` — because filing an unreadable state under "Running now"
/// would be a claim about money that nothing supports.
///
/// ## Which members each role can actually receive
///
/// * **Retailer Owner** — `SCHEDULED`, `ACTIVE`, `PAUSED`, `ENDED`, `CANCELLED`.
///   Not `DRAFT`: both Owner reads join `c.published_version_id = cv.id`, and
///   the `campaigns_draft_has_no_published_version` constraint makes
///   `status = 'DRAFT'` and a published version mutually exclusive.
/// * **Sales Staff** — `ACTIVE` and `SCHEDULED` only. Both staff reads filter
///   `campaign_derived_state(...) in ('ACTIVE', 'SCHEDULED')` in SQL.
///
/// [draft] is still a member, and the grouping switch still has a branch for it.
/// A structurally unreachable value that is nonetheless part of the contract's
/// vocabulary is handled explicitly rather than dropped, so that widening the
/// backend cannot make a campaign silently vanish from a list.
enum CampaignLifecycleState {
  /// Never published. Unreachable through either role's contract — see the
  /// class doc — and carried so the vocabulary is complete.
  draft('DRAFT'),

  /// Published, and its period has not started yet.
  scheduled('SCHEDULED'),

  /// Published, inside its period, not paused and not cancelled.
  active('ACTIVE'),

  /// A human suspended it inside a period that is still running.
  paused('PAUSED'),

  /// Its period has passed. Outranks [paused] in the backend's own ordering.
  ended('ENDED'),

  /// Cancelled outright. Outranks the dates: a cancelled campaign reports
  /// `CANCELLED` whether or not its period has passed.
  cancelled('CANCELLED');

  const CampaignLifecycleState(this.code);

  /// The backend token, exactly as `campaign_derived_state` returns it.
  ///
  /// **Never rendered.** Every screen reads its wording from
  /// `CampaignCopy.lifecycleLabel`, so a database token cannot reach a user
  /// through this field.
  final String code;

  /// The state [raw] names, or null if this build does not recognise it.
  ///
  /// Returns null rather than a fallback member. The caller — always a parser —
  /// turns null into a format error, which is what keeps "a state this build
  /// cannot read" from being presented as any particular state.
  static CampaignLifecycleState? tryFromCode(String raw) {
    for (final CampaignLifecycleState state in values) {
      if (state.code == raw) {
        return state;
      }
    }
    return null;
  }

  /// Whether a sale made now could count toward this campaign.
  ///
  /// True for [active] alone. Deliberately a positive test against one member
  /// rather than an exclusion list, so a member added later cannot arrive at
  /// "running" by failing to match something else.
  bool get isRunning => this == active;

  /// Whether the zero-eligible-product warning applies.
  ///
  /// [active] and [scheduled] only. A paused, ended or cancelled campaign
  /// cannot reward anything regardless of how many products are eligible, so
  /// warning about an empty product set there would describe a consequence that
  /// does not follow.
  bool get warnsOnEmptyProducts => this == active || this == scheduled;
}

/// The management status a human wrote on the campaign row.
///
/// `campaigns.status`, returned by the **Retailer Owner** contract only. Its
/// four values are the ones `campaigns_status_allowed` permits.
///
/// ## It is parsed and it is not rendered
///
/// Nothing on either screen displays this. [CampaignLifecycleState] is the fact
/// a reader needs — it already folds this column together with the period — and
/// showing both would put "Published" beside "Finished" on the same card and
/// invite the reader to work out which one governs.
///
/// It is parsed strictly anyway, because a value outside this set means the
/// deployed contract is not the one this build was written against, and that is
/// worth refusing at the boundary rather than discovering in a wording branch
/// further in.
enum CampaignManagementStatus {
  draft('DRAFT'),
  published('PUBLISHED'),
  paused('PAUSED'),
  cancelled('CANCELLED');

  const CampaignManagementStatus(this.code);

  final String code;

  /// The status [raw] names, or null if this build does not recognise it.
  static CampaignManagementStatus? tryFromCode(String raw) {
    for (final CampaignManagementStatus status in values) {
      if (status.code == raw) {
        return status;
      }
    }
    return null;
  }
}
